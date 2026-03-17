from __future__ import annotations

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Optional

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DEFAULT_SAMPLE_RATE: float = 20.0   # ~20 Hz based on the CSV timestamps
MIN_REP_SAMPLES: int = 5

# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class Sample:
    roll: float
    pitch: float
    yaw: float
    timestamp: float  # raw float timestamp from CSV


@dataclass
class Repetition:
    samples: list[Sample]
    range_of_motion: Optional[float] = None
    concentric_time: Optional[float] = None
    eccentric_time: Optional[float] = None
    timestamp: datetime = field(default_factory=datetime.now)


# ---------------------------------------------------------------------------
# split_reps
# ---------------------------------------------------------------------------

AXES = ["roll", "pitch", "yaw"]
Segment = tuple[int, int, int]  # (start, peak, end)


def split_reps(
    repetition: Repetition,
    sample_rate: float = DEFAULT_SAMPLE_RATE,
) -> list[Repetition]:
    values = _orientation_values(repetition.samples)

    if len(repetition.samples) < MIN_REP_SAMPLES:
        return [repetition]

    # Prefer roll as the dominant axis, since reps typically form a clear "U"
    # in roll. Fall back to automatic selection only if roll is flat.
    if _value_range(values.get("roll", [])) > 0:
        dominant = "roll"
    else:
        dominant = _dominant_axis(values, allowed_axes=["roll", "yaw"])
    axis_values = _smoothed(values[dominant], window=5)
    total_range = _value_range(axis_values)

    if len(axis_values) < MIN_REP_SAMPLES or total_range <= 0:
        return [repetition]

    peaks, valleys = _find_extrema(axis_values)

    if not peaks or len(valleys) < 2:
        return [repetition]

    # Require a slightly larger swing between anchors to count as a rep. This
    # reduces false splits when the curve only has small bumps near the bottom
    # of a "U" but no real second rep.
    min_amplitude = max(0.10, total_range * 0.22)

    valley_segments = _segments_between_anchors(valleys, peaks, axis_values, min_amplitude)
    peak_segments   = _segments_between_anchors(peaks, valleys, axis_values, min_amplitude)

    selected = valley_segments if len(valley_segments) >= len(peak_segments) else peak_segments

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
                timestamp=repetition.timestamp + timedelta(seconds=dt),
            )
        )

    if not result:
        return [repetition]

    # ------------------------------------------------------------------
    # Post‑merge neighbouring reps that are effectively one smooth "U"
    # ------------------------------------------------------------------
    merged: list[Repetition] = [result[0]]
    # Roll / dominant axis is the main motion; use it for tolerance.
    ROLL_GAP_THRESHOLD = 0.15   # radians between boundaries
    TIME_GAP_THRESHOLD = 0.30   # seconds between boundaries
    AXIS_RANGE_THRESHOLD = 1.0  # minimum total swing on dominant axis to allow merge

    axis_name = dominant if dominant in ("roll", "pitch", "yaw") else "roll"

    for rep in result[1:]:
        prev = merged[-1]
        t_gap = rep.samples[0].timestamp - prev.samples[-1].timestamp
        roll_gap = abs(rep.samples[0].roll - prev.samples[-1].roll)

        # Only even consider merging if the reps are very close in time and
        # orientation at the boundary.
        if t_gap <= TIME_GAP_THRESHOLD and roll_gap <= ROLL_GAP_THRESHOLD:
            combined_samples = prev.samples + rep.samples
            axis_vals = [getattr(s, axis_name) for s in combined_samples]
            axis_range = max(axis_vals) - min(axis_vals) if axis_vals else 0.0

            # Additional safeguard: only merge if the overall motion across
            # the combined reps spans at least ~1 rad on the dominant axis.
            if axis_range >= AXIS_RANGE_THRESHOLD:
                merged[-1] = Repetition(
                    samples=combined_samples,
                    timestamp=prev.timestamp,
                )
                continue

        merged.append(rep)

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
    if len(anchors) < 2:
        return []
    segments: list[Segment] = []
    for i in range(len(anchors) - 1):
        start, end = anchors[i], anchors[i + 1]
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


# ---------------------------------------------------------------------------
# Load data & run split_reps
# ---------------------------------------------------------------------------

df = pd.read_csv("formfit_data2.csv")

samples = [
    Sample(roll=row.roll, pitch=row.pitch, yaw=row.yaw, timestamp=row.timestamp)
    for row in df.itertuples()
]

full_rep = Repetition(samples=samples)
reps = split_reps(full_rep, sample_rate=DEFAULT_SAMPLE_RATE)

print(f"Detected {len(reps)} rep(s)")
for i, r in enumerate(reps):
    t_start = r.samples[0].timestamp
    t_end   = r.samples[-1].timestamp
    # Use ASCII arrow for compatibility with Windows console encoding
    print(f"  Rep {i+1}: timestamp {t_start:.3f} -> {t_end:.3f}  ({len(r.samples)} samples)")

# Palette for rep shading (cycles if more reps than colours)
REP_COLORS = ["#a8d8ea", "#fecea8", "#b8f0b8", "#f0b8f0", "#f0f0b8"]

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------

fig, axs = plt.subplots(3, 1, figsize=(12, 9), sharex=True)

# --- Accelerometer ---
axs[0].plot(df["timestamp"], df["ax"], label="ax")
axs[0].plot(df["timestamp"], df["ay"], label="ay")
axs[0].plot(df["timestamp"], df["az"], label="az")
axs[0].set_title("Accelerometer")
axs[0].legend(loc="upper right")

# --- Gyroscope ---
axs[1].plot(df["timestamp"], df["gx"], label="gx")
axs[1].plot(df["timestamp"], df["gy"], label="gy")
axs[1].plot(df["timestamp"], df["gz"], label="gz")
axs[1].set_title("Gyroscope")
axs[1].legend(loc="upper right")

# --- Orientation ---
axs[2].plot(df["timestamp"], df["roll"],  label="roll")
axs[2].plot(df["timestamp"], df["pitch"], label="pitch")
axs[2].plot(df["timestamp"], df["yaw"],   label="yaw")
axs[2].set_title("Orientation")
axs[2].legend(handles=[l for l in axs[2].get_lines() if not l.get_label().startswith("_")], loc="upper right")
axs[2].set_xlabel("Timestamp (s)")

# Shade rep regions across all subplots and add rep labels on bottom plot
legend_patches = []
for i, rep in enumerate(reps):
    color = REP_COLORS[i % len(REP_COLORS)]
    t0 = rep.samples[0].timestamp
    t1 = rep.samples[-1].timestamp
    label = f"Rep {i + 1}"

    for ax in axs:
        ax.axvspan(t0, t1, color=color, alpha=0.35, zorder=0)

    # Vertical boundary lines on orientation subplot
    axs[2].axvline(t0, color="gray", linewidth=0.8, linestyle="--", zorder=1)
    axs[2].axvline(t1, color="gray", linewidth=0.8, linestyle="--", zorder=1)

    # Rep number annotation centred in the shaded region
    mid = (t0 + t1) / 2
    y_pos = axs[2].get_ylim()[1] if axs[2].get_ylim()[1] != 1.0 else 0.9
    axs[2].text(
        mid, axs[2].get_ylim()[0],
        label,
        ha="center", va="bottom",
        fontsize=8, fontweight="bold", color="dimgray",
    )

    legend_patches.append(mpatches.Patch(color=color, alpha=0.5, label=label))

# Rep colour legend on the top subplot
axs[0].legend(
    handles=axs[0].get_lines() + legend_patches,
    loc="upper right",
    fontsize=7,
)

plt.suptitle(f"FormFit Session — {len(reps)} Rep(s) Detected", fontweight="bold")
plt.tight_layout()
plt.savefig("formfit_plot.png", dpi=150)
plt.show()