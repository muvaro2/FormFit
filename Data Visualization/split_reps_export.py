"""split_reps_export.py

Splits each FormFit session CSV into individual per-rep CSVs using the same
rep-detection algorithm as plot_data.py.

Output layout:
    data/split rep files/
        <stem>/
            <stem>_0.csv   ← rep 1
            <stem>_1.csv   ← rep 2
            ...

Usage:
    python3 split_reps_export.py          # processes all 11 session files
    python3 split_reps_export.py <file>   # processes a single CSV
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Optional

import pandas as pd

# ---------------------------------------------------------------------------
# Constants (keep in sync with plot_data.py)
# ---------------------------------------------------------------------------

DEFAULT_SAMPLE_RATE: float = 100.0
MIN_REP_SAMPLES: int = 5
ACCEL_TAIL_MAG_THRESHOLD: float = 0.5
ACCEL_TAIL_QUIET_RUN_SAMPLES: int = 50
ACCEL_TAIL_MAX_TRIM_SAMPLES: int = 300
DEFAULT_MAX_REPS: int = 0

# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class Sample:
    roll: float
    pitch: float
    yaw: float
    t: float


@dataclass
class Repetition:
    samples: list[Sample]
    range_of_motion: Optional[float] = None
    concentric_time: Optional[float] = None
    eccentric_time: Optional[float] = None
    t: datetime = field(default_factory=datetime.now)


# ---------------------------------------------------------------------------
# Algorithm (identical to plot_data.py)
# ---------------------------------------------------------------------------

AXES = ["roll", "pitch", "yaw"]
Segment = tuple[int, int, int]


def split_reps(
    repetition: Repetition,
    sample_rate: float = DEFAULT_SAMPLE_RATE,
    max_reps: int = DEFAULT_MAX_REPS,
) -> list[Repetition]:
    values = _orientation_values(repetition.samples)

    if len(repetition.samples) < MIN_REP_SAMPLES:
        return [repetition]

    dominant = "roll"
    axis_values = _smoothed(values[dominant], window=5)

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

    min_amplitude = max(0.07, total_range * 0.18)

    start_roll = axis_values[0]
    first_deep_valley = next(
        (v for v in valleys if (start_roll - axis_values[v]) > min_amplitude),
        None,
    )
    if first_deep_valley is not None:
        noise_peaks = [
            p for p in peaks
            if p < first_deep_valley
            and abs(axis_values[p] - start_roll) < total_range * 0.03
        ]
        if noise_peaks:
            recovery_threshold = start_roll - total_range * 0.10
            first_recovery = next(
                (p for p in peaks if p > first_deep_valley and axis_values[p] > recovery_threshold),
                None,
            )
            if first_recovery is not None:
                peaks = [p for p in peaks if p >= first_recovery]
                peaks = [0] + peaks

    if not peaks:
        return [repetition]

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

    if not result:
        return [repetition]

    merged: list[Repetition] = [result[0]]

    ROLL_GAP_THRESHOLD  = 0.40
    TIME_GAP_THRESHOLD  = 0.50
    ROLL_CENTER_THRESHOLD = 0.4

    for rep in result[1:]:
        prev = merged[-1]
        t_gap    = rep.samples[0].t - prev.samples[-1].t
        roll_gap = abs(rep.samples[0].roll - prev.samples[-1].roll)

        if t_gap <= TIME_GAP_THRESHOLD and roll_gap <= ROLL_GAP_THRESHOLD:
            boundary_roll = 0.5 * (prev.samples[-1].roll + rep.samples[0].roll)
            if boundary_roll > -ROLL_CENTER_THRESHOLD:
                merged.append(rep)
                continue
            merged[-1] = Repetition(samples=prev.samples + rep.samples, t=prev.t)
            continue

        merged.append(rep)

    MIN_REP_DEPTH = 0.15
    merged = [
        r for r in merged
        if (r.samples[0].roll - min(s.roll for s in r.samples)) >= MIN_REP_DEPTH
    ]

    if not merged:
        return [repetition]

    NOISE_GAP_THRESHOLD   = 3.0
    NOISE_DRIFT_THRESHOLD = 0.40
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
# Helpers
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
    i = 0
    while i < len(anchors) - 1:
        start = anchors[i]
        found = False
        for j in range(i + 1, min(i + 4, len(anchors))):
            end = anchors[j]
            if end <= start + 1:
                continue
            inside = [p for p in opposite if start < p < end]
            if not inside:
                continue
            primary   = max(inside, key=lambda p: abs(values[p] - values[start]))
            baseline  = (values[start] + values[end]) / 2
            amplitude = abs(values[primary] - baseline)
            if amplitude >= min_amplitude:
                segments.append((start, primary, end))
                i = j
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
# Export
# ---------------------------------------------------------------------------

# The 11 session files used in the project
SESSION_FILES = [
    "data/sessions/formfit-20260317-155234-10ms.csv",
    "data/sessions/formfit-20260317-171243-10ms.csv",
    "data/sessions/formfit-20260318-195805-10ms.csv",
    "data/sessions/formfit-20260318-200048-10ms.csv",
    "data/sessions/formfit-20260318-200602-10ms.csv",
    "data/sessions/formfit-20260318-200812-10ms.csv",
    "data/sessions/formfit-20260320-185512-10ms.csv",
    "data/sessions/formfit-20260320-185959-10ms.csv",
    "data/sessions/formfit-20260320-190257-10ms.csv",
    "data/sessions/formfit-20260320-190630-10ms.csv",
    "data/sessions/formfit_data2.csv",
]

OUTPUT_ROOT = "data/split rep files"


def export_reps(csv_path: str) -> None:
    stem = os.path.splitext(os.path.basename(csv_path))[0]
    out_dir = os.path.join(OUTPUT_ROOT, stem)
    os.makedirs(out_dir, exist_ok=True)

    df = pd.read_csv(csv_path)
    df = _trim_tail_until_accel_quiet(df)

    samples = [
        Sample(roll=row.roll, pitch=row.pitch, yaw=row.yaw, t=row.t)
        for row in df.itertuples()
    ]

    full_rep = Repetition(samples=samples)
    reps = split_reps(full_rep, sample_rate=DEFAULT_SAMPLE_RATE, max_reps=DEFAULT_MAX_REPS)

    # Build a t → row-index lookup from the trimmed dataframe
    t_to_idx: dict[float, int] = {row.t: i for i, row in enumerate(df.itertuples())}

    print(f"{stem}: {len(reps)} rep(s)")

    for rep_num, rep in enumerate(reps):
        t_start = rep.samples[0].t
        t_end   = rep.samples[-1].t

        # Collect all original-df rows whose t falls within this rep's range.
        # Using t_start / t_end rather than a lookup set is robust to any
        # floating-point rounding that might prevent exact dict hits.
        mask = (df["t"] >= t_start) & (df["t"] <= t_end)
        rep_df = df.loc[mask].copy().reset_index(drop=True)

        out_path = os.path.join(out_dir, f"{stem}_{rep_num}.csv")
        rep_df.to_csv(out_path, index=False)
        print(f"  rep {rep_num}: {len(rep_df)} rows  →  {out_path}")


def main() -> None:
    if len(sys.argv) >= 2:
        files = sys.argv[1:]
    else:
        files = SESSION_FILES

    for csv_path in files:
        if not os.path.isfile(csv_path):
            print(f"WARNING: file not found — {csv_path}", file=sys.stderr)
            continue
        export_reps(csv_path)

    print("\nDone.")


if __name__ == "__main__":
    main()
