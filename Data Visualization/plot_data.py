from __future__ import annotations

import sys

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Optional

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DEFAULT_SAMPLE_RATE: float = 100.0   # ~100 Hz based on the CSV timestamps
MIN_REP_SAMPLES: int = 5
ACCEL_TAIL_MAG_THRESHOLD: float = 0.5  # per sample: |ax|,|ay|,|az| each below this
ACCEL_TAIL_QUIET_RUN_SAMPLES: int = 50  # consecutive quiet samples required at end of kept data
ACCEL_TAIL_MAX_TRIM_SAMPLES: int = 300
DEFAULT_MAX_REPS: int = 10

# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class Sample:
    roll: float
    pitch: float
    yaw: float
    t: float  # raw float t from CSV


@dataclass
class Repetition:
    samples: list[Sample]
    range_of_motion: Optional[float] = None
    concentric_time: Optional[float] = None
    eccentric_time: Optional[float] = None
    t: datetime = field(default_factory=datetime.now)


# ---------------------------------------------------------------------------
# split_reps
# ---------------------------------------------------------------------------

AXES = ["roll", "pitch", "yaw"]
Segment = tuple[int, int, int]  # (start, peak, end)


def split_reps(
    repetition: Repetition,
    sample_rate: float = DEFAULT_SAMPLE_RATE,
    max_reps: int = DEFAULT_MAX_REPS,
) -> list[Repetition]:
    values = _orientation_values(repetition.samples)

    if len(repetition.samples) < MIN_REP_SAMPLES:
        return [repetition]

    # Always detect reps on roll as the dominant axis. Reps are assumed to be
    # "U" shaped curves in roll, so we hard‑code detection on its minima.
    dominant = "roll"
    axis_values = _smoothed(values[dominant], window=5)

    # Use a percentile-based range so EOF noise spikes don't inflate
    # min_amplitude and cause legitimate reps to fail the threshold.
    sorted_vals = sorted(axis_values)
    _n = len(sorted_vals)
    robust_lo = sorted_vals[max(0, int(_n * 0.02))]
    robust_hi = sorted_vals[min(_n - 1, int(_n * 0.98))]
    total_range = max(robust_hi - robust_lo, _value_range(axis_values) * 0.3)

    if len(axis_values) < MIN_REP_SAMPLES or total_range <= 0:
        return [repetition]

    peaks, valleys = _find_extrema(axis_values)

    if not valleys:
        return [repetition]

    # Require a meaningful swing between anchors to count as a rep, but keep
    # the threshold low enough that smaller warm‑up reps are still detected.
    min_amplitude = max(0.07, total_range * 0.18)

    # Handle recordings that start at neutral: sensor noise in the flat
    # near-zero region creates tiny spurious peaks *before* the first real
    # valley AND sometimes micro-bumps *inside* the valley itself.  Both
    # fragment the first rep's segment so amplitude checks fail.  When noise
    # peaks are present before the first deep valley, strip everything up to
    # (but not including) the first true recovery peak — the first peak where
    # roll has climbed back at least 10 % of total_range above the valley
    # floor.  Replace them all with a single synthetic anchor at index 0.
    # Peaks in the rest of the signal are left completely untouched.
    start_roll = axis_values[0]
    first_deep_valley = next(
        (v for v in valleys if (start_roll - axis_values[v]) > min_amplitude * 0.4),
        None,
    )
    if first_deep_valley is not None:
        noise_peaks = [
            p for p in peaks
            if p < first_deep_valley
            and abs(axis_values[p] - start_roll) < total_range * 0.03
        ]
        if noise_peaks:
            valley_floor = axis_values[first_deep_valley]
            recovery_threshold = valley_floor + total_range * 0.10
            first_recovery = next(
                (p for p in peaks if p > first_deep_valley and axis_values[p] > recovery_threshold),
                None,
            )
            if first_recovery is not None:
                peaks = [p for p in peaks if p >= first_recovery]
                peaks = [0] + peaks

    if not peaks:
        return [repetition]

    # Build reps strictly around minima in roll: each rep is a "U" where the
    # valley is in the middle and peaks are on either side. Concretely, we
    # form segments between successive peaks that contain a valley.
    valley_segments = _segments_between_anchors(peaks, valleys, axis_values, min_amplitude)
    selected = valley_segments

    if not selected:
        return [repetition]

    result: list[Repetition] = []
    n = len(repetition.samples)

    for segment in selected:
        trimmed_start, trimmed_end = _trim_segment(segment, axis_values)
        lower = max(0, trimmed_start)
        upper = min(n - 1, trimmed_end)

        if upper <= lower or (upper - lower + 1) < MIN_REP_SAMPLES:
            continue

        samples = repetition.samples[lower : upper + 1]
        dt = lower / sample_rate if sample_rate > 0 else 0.0
        result.append(
            Repetition(
                samples=samples,
                t=repetition.t + timedelta(seconds=dt),
            )
        )

    # If no valid segments, fall back to a single unsplit repetition.
    if not result:
        return [repetition]

    # ------------------------------------------------------------------
    # Post‑merge neighbouring reps only when a boundary looks like a tiny
    # over‑segmentation (e.g. a single physical rep being cut in half), not
    # when it separates two distinct reps.
    # ------------------------------------------------------------------
    merged: list[Repetition] = [result[0]]

    # We work purely on roll here because detection is hard‑coded to roll.
    # Crucially, we only merge when the time gap between reps is *very* small,
    # which happens when our segmentation created two pieces around the same
    # physical valley/peak. True neighbouring reps have a noticeably larger
    # time gap between them.
    ROLL_GAP_THRESHOLD = 0.40   # radians between boundaries
    TIME_GAP_THRESHOLD = 0.50   # seconds — up to 0.50 s gap can be an over-split artifact
    # Only merge when we are far away from the neutral/zero roll position.
    # True rep boundaries tend to pass near roll ~= 0, while mid‑rep splits
    # happen down in the valley where roll is strongly negative.
    ROLL_CENTER_THRESHOLD = 0.4  # radians

    for rep in result[1:]:
        prev = merged[-1]
        t_gap = rep.samples[0].t - prev.samples[-1].t
        roll_gap = abs(rep.samples[0].roll - prev.samples[-1].roll)

        if t_gap <= TIME_GAP_THRESHOLD and roll_gap <= ROLL_GAP_THRESHOLD:
            # Only merge when the shared boundary is deep in the valley
            # (strongly negative roll). True inter-rep transitions happen near
            # neutral roll (positive/near-zero), so a positive boundary_roll
            # means these are two distinct reps, not an over-split.
            boundary_roll = 0.5 * (prev.samples[-1].roll + rep.samples[0].roll)
            if boundary_roll > -ROLL_CENTER_THRESHOLD:
                merged.append(rep)
                continue

            # Boundary is deep in the valley — treat as two fragments of the
            # same physical rep and stitch them together.
            merged[-1] = Repetition(
                samples=prev.samples + rep.samples,
                t=prev.t,
            )
            continue

        merged.append(rep)

    # ------------------------------------------------------------------
    # Filter out EOF noise reps: a real rep's valley must be meaningfully
    # below where the rep started. If the valley is at (or near) the very
    # first sample, it is almost certainly an upward drift artifact, not a
    # genuine external-rotation repetition.
    # ------------------------------------------------------------------
    MIN_REP_DEPTH = 0.15  # radians — valley must drop this far below rep start
    merged = [
        r for r in merged
        if (r.samples[0].roll - min(s.roll for s in r.samples)) >= MIN_REP_DEPTH
    ]

    if not merged:
        return [repetition]

    # ------------------------------------------------------------------
    # Detect end-of-set noise: after a long rest (> 3 s gap) the user may
    # make incidental movements that look rep-shaped but aren't.  The tell
    # is that the arm doesn't return to its starting position — the rep's
    # end roll differs significantly from its start roll.  When we see a
    # rep with both a large gap before it AND high roll drift, the exercise
    # set has ended: drop that rep and everything after it.
    # ------------------------------------------------------------------
    NOISE_GAP_THRESHOLD   = 3.0   # seconds — unusually long rest
    NOISE_DRIFT_THRESHOLD = 0.40  # radians — arm didn't return to start
    for idx in range(1, len(merged)):
        gap   = merged[idx].samples[0].t - merged[idx - 1].samples[-1].t
        drift = abs(merged[idx].samples[-1].roll - merged[idx].samples[0].roll)
        if gap > NOISE_GAP_THRESHOLD and drift > NOISE_DRIFT_THRESHOLD:
            merged = merged[:idx]
            break

    if max_reps > 0:
        return merged[:max_reps]
    return merged


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

def _orientation_values(samples: list[Sample]) -> dict[str, list[float]]:
    result: dict[str, list[float]] = {"roll": [], "pitch": [], "yaw": []}
    for s in samples:
        result["roll"].append(s.roll)
        result["pitch"].append(s.pitch)
        result["yaw"].append(s.yaw)
    return result


def _value_range(values: list[float]) -> float:
    if not values:
        return 0.0
    return max(values) - min(values)


def _dominant_axis(
    values: dict[str, list[float]],
    allowed_axes: list[str] = AXES,
) -> str:
    best_axis = allowed_axes[0]
    best_range = float("-inf")
    for axis in allowed_axes:
        r = _value_range(values.get(axis, []))
        if r > best_range:
            best_range = r
            best_axis = axis
    return best_axis


def _smoothed(values: list[float], window: int = 5) -> list[float]:
    if not values or window <= 1:
        return list(values)
    half = max(1, window // 2)
    out = []
    for i in range(len(values)):
        start = max(0, i - half)
        end   = min(len(values) - 1, i + half)
        chunk = values[start : end + 1]
        out.append(sum(chunk) / len(chunk))
    return out


def _find_extrema(values: list[float]) -> tuple[list[int], list[int]]:
    if len(values) < 3:
        return [], []
    peaks:   list[int] = []
    valleys: list[int] = []
    for i in range(1, len(values) - 1):
        prev, cur, nxt = values[i - 1], values[i], values[i + 1]
        if cur > prev and cur >= nxt:
            peaks.append(i)
        if cur < prev and cur <= nxt:
            valleys.append(i)
    return peaks, valleys



def _segments_between_anchors(
    anchors: list[int],
    opposite: list[int],
    values: list[float],
    min_amplitude: float,
) -> list[Segment]:
    """Build rep segments between anchor peaks.

    For each left anchor we try the next few right anchors in order
    (consecutive first, then up to 3 peaks ahead).  This lets the algorithm
    skip intermediate peaks that are inside a valley and would produce a
    misleadingly small baseline, so the real rep is still detected.
    """
    if len(anchors) < 2:
        return []
    segments: list[Segment] = []
    i = 0
    while i < len(anchors) - 1:
        start = anchors[i]
        found = False
        # Try anchors[i+1], anchors[i+2], anchors[i+3] as the right endpoint.
        # Stop as soon as we find a segment that passes the amplitude check.
        for j in range(i + 1, min(i + 4, len(anchors))):
            end = anchors[j]
            if end <= start + 1:
                continue
            inside = [p for p in opposite if start < p < end]
            if not inside:
                continue
            primary = max(inside, key=lambda p: abs(values[p] - values[start]))
            baseline  = (values[start] + values[end]) / 2
            amplitude = abs(values[primary] - baseline)
            if amplitude >= min_amplitude:
                segments.append((start, primary, end))
                i = j   # advance left anchor to the right endpoint we just used
                found = True
                break
        if not found:
            i += 1
    return segments


def _trim_segment(segment: Segment, values: list[float]) -> tuple[int, int]:
    start, peak, end = segment
    baseline       = (values[start] + values[end]) / 2
    full_amplitude = abs(values[peak] - baseline)
    margin         = max(0.03, full_amplitude * 0.15)

    while start < peak and abs(values[start] - baseline) < margin:
        start += 1
    while end > peak and abs(values[end] - baseline) < margin:
        end -= 1

    return start, end


def _trim_tail_until_accel_quiet(
    frame: pd.DataFrame,
    mag_threshold: float = ACCEL_TAIL_MAG_THRESHOLD,
    quiet_run: int = ACCEL_TAIL_QUIET_RUN_SAMPLES,
    max_trim: int = ACCEL_TAIL_MAX_TRIM_SAMPLES,
) -> pd.DataFrame:
    """Trim the tail so the kept data ends with ``quiet_run`` consecutive quiet samples.

    A sample is quiet when |ax|, |ay|, and |az| are all below ``mag_threshold``.
    Chooses the longest kept prefix (fewest rows dropped) that satisfies this,
    with at most ``max_trim`` rows removed. If none qualifies, drops ``max_trim``
    rows from the end.
    """
    if frame.empty or max_trim <= 0:
        return frame
    n = len(frame)
    if n < quiet_run:
        return frame

    def _suffix_quiet(end: int) -> bool:
        chunk = frame.iloc[end - quiet_run : end][["ax", "ay", "az"]].abs()
        return bool((chunk < mag_threshold).all(axis=None))

    min_end = max(quiet_run, n - max_trim)
    for end in range(n, min_end - 1, -1):
        if _suffix_quiet(end):
            return frame.iloc[:end].copy().reset_index(drop=True)

    fallback_end = max(0, n - max_trim)
    return frame.iloc[:fallback_end].copy().reset_index(drop=True)


# ---------------------------------------------------------------------------
# Load data & run split_reps
# ---------------------------------------------------------------------------


def _parse_cli() -> tuple[str, int]:
    """argv: plot_data.py <csv_path> [max_reps]. max_reps defaults to DEFAULT_MAX_REPS."""
    if len(sys.argv) < 2:
        print(
            "Usage: python plot_data.py <csv_path> [max_reps]",
            file=sys.stderr,
        )
        sys.exit(2)
    csv_path = sys.argv[1]
    if len(sys.argv) >= 3:
        try:
            n = int(sys.argv[2])
        except ValueError:
            print(
                "Usage: python plot_data.py <csv_path> [max_reps]",
                file=sys.stderr,
            )
            sys.exit(2)
        if n < 1:
            print("max_reps must be >= 1", file=sys.stderr)
            sys.exit(2)
        return csv_path, n
    return csv_path, DEFAULT_MAX_REPS


_CSV_PATH, _MAX_REPS = _parse_cli()

df = pd.read_csv(_CSV_PATH)
df = _trim_tail_until_accel_quiet(df)

samples = [
    Sample(roll=row.roll, pitch=row.pitch, yaw=row.yaw, t=row.t)
    for row in df.itertuples()
]

full_rep = Repetition(samples=samples)
reps = split_reps(full_rep, sample_rate=DEFAULT_SAMPLE_RATE, max_reps=_MAX_REPS)

print(f"Detected {len(reps)} rep(s)")
for i, r in enumerate(reps):
    t_start = r.samples[0].t
    t_end   = r.samples[-1].t
    # Use ASCII arrow for compatibility with Windows console encoding
    print(f"  Rep {i+1}: t {t_start:.3f} -> {t_end:.3f}  ({len(r.samples)} samples)")

# ---------------------------------------------------------------------------
# Eccentric scoring
# ---------------------------------------------------------------------------

ECCENTRIC_COLORS = {
    "good":         "#7dd87d",   # green
    "slightly_fast": "#f5c842",  # yellow
    "too_fast":     "#e8675a",   # red
}

ECCENTRIC_LABELS = {
    "good":         "Good eccentric",
    "slightly_fast": "Eccentric slightly too fast",
    "too_fast":     "Eccentric too fast",
}


def _eccentric_time(rep: Repetition) -> float:
    """Return the duration (seconds) of the eccentric (return) phase.

    For an external shoulder rotation the user starts at neutral, rotates
    outward first (concentric: peak → valley in roll), then returns to neutral
    (eccentric: valley → peak in roll).  The eccentric phase therefore runs
    from the roll minimum to the end of the rep.
    """
    rolls = [s.roll for s in rep.samples]
    valley_idx = rolls.index(min(rolls))
    return rep.samples[-1].t - rep.samples[valley_idx].t


def _eccentric_score(duration: float) -> str:
    if duration >= 3.0:
        return "good"
    if duration >= 2.0:
        return "slightly_fast"
    return "too_fast"

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------

fig, axs = plt.subplots(3, 1, figsize=(12, 9), sharex=True)

# --- Accelerometer ---
axs[0].plot(df["t"], df["ax"], label="ax")
axs[0].plot(df["t"], df["ay"], label="ay")
axs[0].plot(df["t"], df["az"], label="az")
axs[0].set_title("Accelerometer")
axs[0].legend(loc="upper right")

# --- Gyroscope ---
axs[1].plot(df["t"], df["gx"], label="gx")
axs[1].plot(df["t"], df["gy"], label="gy")
axs[1].plot(df["t"], df["gz"], label="gz")
axs[1].set_title("Gyroscope")
axs[1].legend(loc="upper right")

# --- Orientation ---
axs[2].plot(df["t"], df["roll"],  label="roll")
axs[2].plot(df["t"], df["pitch"], label="pitch")
axs[2].plot(df["t"], df["yaw"],   label="yaw")
axs[2].set_title("Orientation")
axs[2].legend(handles=[l for l in axs[2].get_lines() if not l.get_label().startswith("_")], loc="upper right")
axs[2].set_xlabel("Timestamp (s)")

# ---------------------------------------------------------------------------
# Shade rep regions and annotate with eccentric scores
# ---------------------------------------------------------------------------

# Legend patches for the top subplot (sensor lines + eccentric quality key)
legend_patches = []

for i, rep in enumerate(reps):
    ecc_dur   = _eccentric_time(rep)
    score_key = _eccentric_score(ecc_dur)
    color     = ECCENTRIC_COLORS[score_key]

    t0  = rep.samples[0].t
    t1  = rep.samples[-1].t
    mid = (t0 + t1) / 2

    # Shade all three subplots with the score colour
    for ax in axs:
        ax.axvspan(t0, t1, color=color, alpha=0.28, zorder=0)

    # Dashed boundary lines on the orientation subplot
    axs[2].axvline(t0, color="gray", linewidth=0.8, linestyle="--", zorder=1)
    axs[2].axvline(t1, color="gray", linewidth=0.8, linestyle="--", zorder=1)

    # Annotation box: rep number + eccentric time + verdict
    y_min, y_max = axs[2].get_ylim()
    annotation_y = y_min + (y_max - y_min) * 0.04   # just above the bottom edge

    axs[2].text(
        mid, annotation_y,
        f"Rep {i + 1}\n{ecc_dur:.2f}s\n{ECCENTRIC_LABELS[score_key]}",
        ha="center", va="bottom",
        fontsize=7, fontweight="bold",
        color="white",
        bbox=dict(
            boxstyle="round,pad=0.3",
            facecolor=color,
            edgecolor="none",
            alpha=0.85,
        ),
        zorder=3,
    )

    legend_patches.append(
        mpatches.Patch(color=color, alpha=0.7, label=f"Rep {i + 1}  ({ecc_dur:.2f}s — {ECCENTRIC_LABELS[score_key]})")
    )

# Eccentric quality colour key (shown once, below sensor lines)
quality_legend = [
    mpatches.Patch(color=ECCENTRIC_COLORS["good"],          alpha=0.7, label="Good eccentric  (≥ 3.0 s)"),
    mpatches.Patch(color=ECCENTRIC_COLORS["slightly_fast"], alpha=0.7, label="Eccentric slightly too fast  (2.0 – 3.0 s)"),
    mpatches.Patch(color=ECCENTRIC_COLORS["too_fast"],      alpha=0.7, label="Eccentric too fast  (< 2.0 s)"),
]

# Top subplot: sensor lines + per-rep legend
axs[0].legend(
    handles=axs[0].get_lines() + legend_patches,
    loc="upper right",
    fontsize=7,
)

# Bottom subplot: quality colour key
axs[2].legend(
    handles=[l for l in axs[2].get_lines() if not l.get_label().startswith("_")] + quality_legend,
    loc="lower right",
    fontsize=7,
)

import os as _os
_plot_name = _os.path.splitext(_os.path.basename(_CSV_PATH))[0] + "_plot.png"
plt.suptitle(f"FormFit Session — {len(reps)} Rep(s) Detected", fontweight="bold")
plt.tight_layout()
plt.savefig(_plot_name, dpi=150)
plt.show()