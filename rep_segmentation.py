"""Segment FormFit shoulder-rotation sessions into model-ready rep windows.

The pipeline validates and smooths roll, pairs motion anchors, refines the
boundaries, repairs likely over-splits, and filters incomplete movement.
"""

from __future__ import annotations

import math
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field, replace
from enum import StrEnum
from types import MappingProxyType

__all__ = [
    "Diagnostics",
    "DropReason",
    "InvalidSession",
    "RepSegment",
    "Sample",
    "SegmentationConfig",
    "SegmentationResult",
    "ValidatedSession",
    "parse_samples",
    "segment_session",
    "validate_session",
]


# Input validation


class InvalidSession(ValueError):
    """Invalid session data with a machine-readable error code."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code


@dataclass(frozen=True, slots=True)
class Sample:
    """Orientation sample; `t` is seconds from recording start."""

    t: float
    roll: float
    pitch: float
    yaw: float


class ValidatedSession(tuple[Sample, ...]):
    """Immutable sample buffer returned by `validate_session`."""

    __slots__ = ()


def validate_session(
    rows: Iterable[Sample],
    *,
    max_samples: int = 360_000,  # 1 hour at 100 Hz; a PT set is ~30 s
) -> ValidatedSession:
    """Validate size, finite fields, and non-decreasing timestamps."""
    # Recheck marked buffers; the tuple subclass can still be built directly.
    validated_input = rows if isinstance(rows, ValidatedSession) else None
    samples: list[Sample] = []
    previous_t: float | None = None
    for index, sample in enumerate(rows):
        if index >= max_samples:
            raise InvalidSession(
                "session_too_long",
                f"exceeds {max_samples} samples; refusing to buffer the rest",
            )
        for name, value in (
            ("t", sample.t),
            ("roll", sample.roll),
            ("pitch", sample.pitch),
            ("yaw", sample.yaw),
        ):
            if not math.isfinite(value):
                raise InvalidSession(
                    "non_finite_value",
                    f"row {index} has non-finite {name}={value!r}",
                )
        if previous_t is not None and sample.t < previous_t:
            raise InvalidSession(
                "non_monotonic_time",
                f"row {index} moves backwards in time ({sample.t} after {previous_t})",
            )
        previous_t = sample.t
        if validated_input is None:
            samples.append(sample)
    if validated_input is not None:
        return validated_input
    return ValidatedSession(samples)


_ORIENTATION_FIELDS = ("roll", "pitch", "yaw")


def parse_samples(
    rows: Iterable[Mapping[str, str | None]],
    *,
    sample_rate_hz: float = 100.0,
    max_samples: int = 360_000,
) -> ValidatedSession:
    """Parse CSV-style rows; derive timestamps for fixed-rate legacy data."""
    if not math.isfinite(sample_rate_hz) or sample_rate_hz <= 0:
        raise ValueError("sample_rate_hz must be finite and positive")

    def parsed() -> Iterable[Sample]:
        for index, row in enumerate(rows):
            values: dict[str, float] = {}
            for name in _ORIENTATION_FIELDS:
                raw = row.get(name)
                if raw is None or raw == "":
                    raise InvalidSession(
                        "missing_field", f"row {index} is missing {name}"
                    )
                try:
                    values[name] = float(raw)
                except (TypeError, ValueError):
                    raise InvalidSession(
                        "non_numeric_field", f"row {index} has {name}={raw!r}"
                    ) from None

            # Older fixed-rate captures did not store timestamps.
            raw_t = row.get("t")
            if raw_t is None or raw_t == "":
                t = index / sample_rate_hz
            else:
                try:
                    t = float(raw_t)
                except (TypeError, ValueError):
                    raise InvalidSession(
                        "non_numeric_field", f"row {index} has t={raw_t!r}"
                    ) from None
            yield Sample(t=t, **values)

    return validate_session(parsed(), max_samples=max_samples)


# Configuration

# Non-negative magnitude thresholds
_MAGNITUDE_THRESHOLDS = (
    "range_floor_fraction",
    "min_amplitude_fraction",
    "min_amplitude_floor",
    "lead_in_noise_fraction",
    "lead_in_recovery_fraction",
    "tighten_margin_fraction",
    "tighten_margin_floor",
    "merge_max_time_gap_s",
    "merge_max_roll_gap",
    "merge_min_valley_depth",
    "min_rep_depth",
    "set_end_rest_gap_s",
    "set_end_drift",
)


@dataclass(frozen=True, slots=True)
class SegmentationConfig:
    """External-rotation thresholds; orientation values are radians."""

    # Physical plausibility floor
    min_rep_samples: int = 5

    # Centered smoothing; odd width required
    smoothing_window: int = 5

    # Robust range, excluding isolated spikes
    range_low_quantile: float = 0.02
    range_high_quantile: float = 0.98

    # Fallback for short sessions with collapsed quantiles
    range_floor_fraction: float = 0.30

    # Minimum shoulder-to-valley swing
    min_amplitude_fraction: float = 0.18
    min_amplitude_floor: float = 0.07

    # Initial rest/jitter handling
    lead_in_noise_fraction: float = 0.03
    lead_in_recovery_fraction: float = 0.10

    # Bounded skip over interior bumps
    max_anchor_lookahead: int = 3

    # Boundary trim from peak anchors toward motion
    tighten_margin_fraction: float = 0.15
    tighten_margin_floor: float = 0.03

    # Over-split merge conditions
    merge_max_time_gap_s: float = 0.50
    merge_max_roll_gap: float = 0.40
    merge_min_valley_depth: float = 0.40

    # Minimum depth from segment start
    min_rep_depth: float = 0.15

    # Post-rest movement with unmatched endpoint
    set_end_rest_gap_s: float = 3.00
    set_end_drift: float = 0.40

    def __post_init__(self) -> None:
        if self.smoothing_window < 1:
            raise ValueError("smoothing_window must be >= 1")
        if self.smoothing_window % 2 == 0:
            raise ValueError("smoothing_window must be odd for a centered window")
        if self.min_rep_samples < 3:
            raise ValueError("min_rep_samples must be >= 3 to admit an extremum")
        if not 0.0 <= self.range_low_quantile < self.range_high_quantile <= 1.0:
            raise ValueError("quantiles must satisfy 0 <= low < high <= 1")
        if self.max_anchor_lookahead < 1:
            raise ValueError("max_anchor_lookahead must be >= 1")
        for name in _MAGNITUDE_THRESHOLDS:
            value: float = getattr(self, name)
            if not math.isfinite(value) or value < 0.0:
                raise ValueError(f"{name} must be finite and non-negative")


# Results


class DropReason(StrEnum):
    """Candidate rejection stage."""

    BELOW_AMPLITUDE = "below_amplitude"
    TOO_SHORT = "too_short"
    TOO_SHALLOW = "too_shallow"
    AFTER_SET_END = "after_set_end"


@dataclass(frozen=True, slots=True)
class RepSegment:
    """Half-open sample range with its deepest roll index."""

    start: int
    end: int
    valley: int

    def __post_init__(self) -> None:
        if not self.start <= self.valley < self.end:
            raise ValueError(f"valley {self.valley} outside [{self.start}, {self.end})")

    def __len__(self) -> int:
        return self.end - self.start

    def samples(self, session: Sequence[Sample]) -> Sequence[Sample]:
        return session[self.start : self.end]

    def range_of_motion(self, session: Sequence[Sample]) -> float:
        rolls = [s.roll for s in self.samples(session)]
        return max(rolls) - min(rolls)

    def concentric_time(self, session: Sequence[Sample]) -> float:
        return session[self.valley].t - session[self.start].t

    def eccentric_time(self, session: Sequence[Sample]) -> float:
        return session[self.end - 1].t - session[self.valley].t


_NO_DROPS: Mapping[DropReason, int] = MappingProxyType({})


@dataclass(frozen=True, slots=True)
class Diagnostics:
    """Candidate, merge, and rejection counts."""

    candidates: int = 0
    merged_oversplits: int = 0
    dropped: Mapping[DropReason, int] = field(default=_NO_DROPS)

    def _with_drop(self, reason: DropReason, count: int) -> Diagnostics:
        if count <= 0:
            return self
        merged = dict(self.dropped)
        merged[reason] = merged.get(reason, 0) + count
        return replace(self, dropped=MappingProxyType(merged))

    def reconciles_with(self, kept: int) -> bool:
        return (
            self.candidates - sum(self.dropped.values()) - self.merged_oversplits
            == kept
        )


@dataclass(frozen=True, slots=True)
class SegmentationResult:
    session: ValidatedSession
    reps: tuple[RepSegment, ...]
    diagnostics: Diagnostics


# Pipeline


def segment_session(
    session: ValidatedSession | Sequence[Sample],
    config: SegmentationConfig | None = None,
) -> SegmentationResult:
    """Split one session into repetition ranges."""
    config = config or SegmentationConfig()
    buffer = validate_session(session)
    empty = SegmentationResult(buffer, (), Diagnostics())
    if len(buffer) < config.min_rep_samples:
        return empty

    # Smooth noise, then scale detection thresholds to this recording.
    roll = _rolling_mean([s.roll for s in buffer], config.smoothing_window)
    span = _robust_range(roll, config)
    if span <= 0.0:
        return empty

    # Opening orientation is the patient-relative rest reference.
    neutral = roll[0]

    peaks, valleys = _find_extrema(roll)
    if not peaks or not valleys:
        return empty

    min_amplitude = max(
        config.min_amplitude_floor, span * config.min_amplitude_fraction
    )

    # Build candidates while treating small opening peaks as rest jitter.
    peaks = _prune_lead_in_noise(roll, peaks, valleys, span, min_amplitude, config)

    segments, below_amplitude = _pair_anchors(
        roll, peaks, valleys, min_amplitude, config
    )
    diagnostics = Diagnostics(candidates=len(segments) + below_amplitude)
    diagnostics = diagnostics._with_drop(DropReason.BELOW_AMPLITUDE, below_amplitude)

    # Refine model windows, then repair false splits near full rotation.
    segments = [_tighten(seg, roll, config) for seg in segments]
    kept = [seg for seg in segments if len(seg) >= config.min_rep_samples]
    diagnostics = diagnostics._with_drop(
        DropReason.TOO_SHORT, len(segments) - len(kept)
    )

    kept, merges = _merge_oversplits(kept, roll, buffer, neutral, config)
    diagnostics = replace(diagnostics, merged_oversplits=merges)

    # Remove partial movement and rep-shaped activity after the set.
    deep = [seg for seg in kept if _depth(seg, roll) >= config.min_rep_depth]
    diagnostics = diagnostics._with_drop(DropReason.TOO_SHALLOW, len(kept) - len(deep))

    final = _truncate_at_set_end(deep, roll, buffer, config)
    diagnostics = diagnostics._with_drop(
        DropReason.AFTER_SET_END, len(deep) - len(final)
    )

    _check_invariants(final, len(buffer), diagnostics, config)
    return SegmentationResult(buffer, tuple(final), diagnostics)


# Stages


def _rolling_mean(values: Sequence[float], window: int) -> list[float]:
    """Centered moving average; O(n) prefix sum."""
    n = len(values)
    if n == 0 or window <= 1:
        return list(values)
    half = max(1, window // 2)
    prefix = [0.0] * (n + 1)
    for i, value in enumerate(values):
        prefix[i + 1] = prefix[i] + value
    out: list[float] = []
    for i in range(n):
        lo = max(0, i - half)
        hi = min(n, i + half + 1)
        out.append((prefix[hi] - prefix[lo]) / (hi - lo))
    return out


def _robust_range(values: Sequence[float], config: SegmentationConfig) -> float:
    """Quantile range with a raw peak-to-peak floor; O(n log n)."""
    ordered = sorted(values)
    last = len(ordered) - 1
    lo = ordered[max(0, min(last, int(last * config.range_low_quantile)))]
    hi = ordered[max(0, min(last, int(last * config.range_high_quantile)))]
    raw = ordered[-1] - ordered[0]
    return max(hi - lo, raw * config.range_floor_fraction)


def _find_extrema(values: Sequence[float]) -> tuple[list[int], list[int]]:
    """Interior extrema; first index for plateaus."""
    peaks: list[int] = []
    valleys: list[int] = []
    n = len(values)
    i = 1
    while i < n - 1:
        previous, current = values[i - 1], values[i]
        if current == previous:
            i += 1
            continue
        # Treat a flat top or bottom as one extremum at its first sample.
        end = i
        while end + 1 < n and values[end + 1] == current:
            end += 1
        if end + 1 >= n:
            break  # trailing plateau
        following = values[end + 1]
        if current > previous and current > following:
            peaks.append(i)
        elif current < previous and current < following:
            valleys.append(i)
        i = end + 1
    return peaks, valleys


def _prune_lead_in_noise(
    values: Sequence[float],
    peaks: list[int],
    valleys: list[int],
    span: float,
    min_amplitude: float,
    config: SegmentationConfig,
) -> list[int]:
    """Replace initial rest jitter with an anchor at sample zero."""
    start = values[0]
    first_deep = next((v for v in valleys if start - values[v] > min_amplitude), None)
    if first_deep is None:
        return peaks

    noise_cutoff = span * config.lead_in_noise_fraction
    leading = [p for p in peaks if p < first_deep]
    if any(abs(values[p] - start) >= noise_cutoff for p in leading):
        return peaks  # non-jitter peak before first valley

    # Require recovery near the same patient-relative rest level.
    recovery = start - span * config.lead_in_recovery_fraction
    first_recovery = next(
        (p for p in peaks if p > first_deep and values[p] > recovery), None
    )
    if first_recovery is None:
        return peaks
    return [0] + [p for p in peaks if p >= first_recovery]


def _pair_anchors(
    values: Sequence[float],
    peaks: Sequence[int],
    valleys: Sequence[int],
    min_amplitude: float,
    config: SegmentationConfig,
) -> tuple[list[RepSegment], int]:
    """Greedy peak pairing with bounded lookahead over interior bumps."""
    segments: list[RepSegment] = []
    below_amplitude = 0
    i = 0
    valley_cursor = 0
    while i < len(peaks) - 1:
        left = peaks[i]

        # The cursor never rewinds, keeping the pairing pass linear.
        while valley_cursor < len(valleys) and valleys[valley_cursor] <= left:
            valley_cursor += 1
        candidate_cursor = valley_cursor
        valley: int | None = None
        advanced = False
        bracketed = False
        for j in range(i + 1, min(i + 1 + config.max_anchor_lookahead, len(peaks))):
            right = peaks[j]
            if right <= left + 1:
                continue

            # Keep the deepest valley seen before each possible right shoulder.
            while candidate_cursor < len(valleys) and valleys[candidate_cursor] < right:
                candidate = valleys[candidate_cursor]
                if valley is None or abs(values[candidate] - values[left]) > abs(
                    values[valley] - values[left]
                ):
                    valley = candidate
                candidate_cursor += 1
            if valley is None:
                continue
            bracketed = True
            baseline = (values[left] + values[right]) / 2.0
            if abs(values[valley] - baseline) >= min_amplitude:
                segments.append(RepSegment(left, right, valley))
                i = j  # Next rep may reuse this peak; closing edge stays exclusive.
                advanced = True
                break
        if not advanced:
            below_amplitude += bracketed
            i += 1
    return segments, below_amplitude


def _tighten(
    segment: RepSegment, values: Sequence[float], config: SegmentationConfig
) -> RepSegment:
    """Trim flat approach and recovery from a candidate."""
    baseline = (values[segment.start] + values[segment.end - 1]) / 2.0
    amplitude = abs(values[segment.valley] - baseline)
    margin = max(
        config.tighten_margin_floor, amplitude * config.tighten_margin_fraction
    )

    # Remove flat approach and recovery; the returned end stays exclusive.
    start = segment.start
    while start < segment.valley and abs(values[start] - baseline) < margin:
        start += 1
    end = segment.end - 1
    while end > segment.valley and abs(values[end] - baseline) < margin:
        end -= 1
    return RepSegment(start, end + 1, segment.valley)


def _merge_oversplits(
    segments: Sequence[RepSegment],
    values: Sequence[float],
    session: Sequence[Sample],
    neutral: float,
    config: SegmentationConfig,
) -> tuple[list[RepSegment], int]:
    """Merge adjacent fragments whose boundary remains below rest."""
    if not segments:
        return [], 0
    merge_below = neutral - config.merge_min_valley_depth
    merged = [segments[0]]
    count = 0
    for segment in segments[1:]:
        previous = merged[-1]
        time_gap = session[segment.start].t - session[previous.end - 1].t
        roll_gap = abs(values[segment.start] - values[previous.end - 1])
        boundary = (values[previous.end - 1] + values[segment.start]) / 2.0

        # A real inter-rep boundary returns near rest; an over-split stays low.
        joinable = (
            time_gap <= config.merge_max_time_gap_s
            and roll_gap <= config.merge_max_roll_gap
            and boundary <= merge_below
        )
        if joinable:
            deeper = min(previous.valley, segment.valley, key=lambda v: values[v])
            merged[-1] = RepSegment(previous.start, segment.end, deeper)
            count += 1
        else:
            merged.append(segment)
    return merged, count


def _depth(segment: RepSegment, values: Sequence[float]) -> float:
    """Roll displacement below the segment start."""
    return values[segment.start] - min(values[segment.start : segment.end])


def _truncate_at_set_end(
    segments: Sequence[RepSegment],
    values: Sequence[float],
    session: Sequence[Sample],
    config: SegmentationConfig,
) -> list[RepSegment]:
    """Stop at post-rest motion that does not return to its start level."""
    for i in range(1, len(segments)):
        gap = session[segments[i].start].t - session[segments[i - 1].end - 1].t
        drift = abs(values[segments[i].end - 1] - values[segments[i].start])

        # Long-rest motion counts only when it returns to its starting level.
        if gap > config.set_end_rest_gap_s and drift > config.set_end_drift:
            return list(segments[:i])
    return list(segments)


def _check_invariants(
    segments: Sequence[RepSegment],
    length: int,
    diagnostics: Diagnostics,
    config: SegmentationConfig,
) -> None:
    """Internal segment and diagnostics invariants."""
    previous_end = 0
    for segment in segments:
        assert 0 <= segment.start < segment.end <= length, "segment out of bounds"
        assert segment.start >= previous_end, "segments overlap or are unordered"
        assert len(segment) >= config.min_rep_samples, "segment shorter than minimum"
        previous_end = segment.end
    assert diagnostics.reconciles_with(len(segments)), (
        "diagnostics do not account for every candidate"
    )
