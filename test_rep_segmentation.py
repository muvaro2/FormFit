"""Tests for `rep_segmentation`.

Synthetic traces isolate edge cases deterministically. The segmenter was also
evaluated on 50+ real recordings with known expected repetition counts. Selected
common and difficult cases appear in the README; recordings used for
final evaluation were not used to tune thresholds. Source recordings are not
included.
"""

from __future__ import annotations

import math
from collections.abc import Iterator, Sequence
from itertools import pairwise
from typing import Any, overload

import pytest

from rep_segmentation import (
    Diagnostics,
    DropReason,
    InvalidSession,
    RepSegment,
    Sample,
    SegmentationConfig,
    ValidatedSession,
    parse_samples,
    segment_session,
    validate_session,
)

SAMPLE_RATE = 100.0  # Hz, matching the watch collector
NEUTRAL = 0.0
DEPTH = 1.2  # radians; a full external rotation


def _rep(
    duration_s: float = 2.0,
    depth: float = DEPTH,
    neutral: float = NEUTRAL,
) -> list[float]:
    """One rep as a smooth cosine dip from `neutral` down to `neutral - depth`."""
    n = max(2, int(duration_s * SAMPLE_RATE))
    return [
        neutral - depth * 0.5 * (1.0 - math.cos(2.0 * math.pi * i / n))
        for i in range(n)
    ]


def _rest(duration_s: float, level: float = NEUTRAL) -> list[float]:
    """Held position with deterministic sensor jitter."""
    n = max(1, int(duration_s * SAMPLE_RATE))
    return [level + 0.004 * math.sin(i * 2.3) for i in range(n)]


def _session(rolls: list[float]) -> list[Sample]:
    return [
        Sample(t=i / SAMPLE_RATE, roll=roll, pitch=0.0, yaw=0.0)
        for i, roll in enumerate(rolls)
    ]


def _set_of(count: int, *, rest_s: float = 0.8) -> list[Sample]:
    rolls: list[float] = list(_rest(0.5))
    for _ in range(count):
        rolls += _rep()
        rolls += _rest(rest_s)
    return _session(rolls)


# Core counting


@pytest.mark.parametrize("count", [1, 3, 5, 10])
def test_counts_a_clean_set(count: int) -> None:
    result = segment_session(_set_of(count))
    assert len(result.reps) == count


def test_reps_are_ordered_and_disjoint() -> None:
    reps = segment_session(_set_of(5)).reps
    for earlier, later in pairwise(reps):
        assert earlier.end <= later.start


def test_valley_is_the_deepest_point_of_its_rep() -> None:
    result = segment_session(_set_of(4))
    for rep in result.reps:
        rolls = [s.roll for s in rep.samples(result.session)]
        assert result.session[rep.valley].roll == pytest.approx(min(rolls), abs=1e-9)


def test_segments_stay_inside_the_buffer() -> None:
    result = segment_session(_set_of(6))
    for rep in result.reps:
        assert 0 <= rep.start < rep.end <= len(result.session)


# Segmentation behavior


def test_finds_the_first_rep_when_recording_starts_at_rest() -> None:
    jitter = [0.004 * math.sin(i) for i in range(120)]
    session = _session(jitter + _rep() + _rest(0.8) + _rep() + _rest(0.5))
    assert len(segment_session(session).reps) == 2


def test_offset_neutral_does_not_suppress_detection() -> None:
    offset = -0.15
    rolls = _rest(0.5, offset)
    for _ in range(3):
        rolls += _rep(neutral=offset) + _rest(0.8, offset)
    assert len(segment_session(_session(rolls)).reps) == 3


def test_adding_a_constant_orientation_offset_preserves_boundaries() -> None:
    original = _set_of(4)
    shifted = [
        Sample(t=s.t, roll=s.roll + 0.73, pitch=s.pitch, yaw=s.yaw) for s in original
    ]
    assert segment_session(original).reps == segment_session(shifted).reps


def _tremor_rep() -> list[float]:
    """Rep with a brief rise near full rotation."""
    return (
        _rep(duration_s=1.2, depth=1.2)[:60]  # down to full rotation
        + [-1.2 + 0.5 * (1 - math.cos(2 * math.pi * i / 40)) * 0.5 for i in range(40)]
        + [-0.95 - 0.25 * (1 - math.cos(2 * math.pi * i / 40)) * 0.5 for i in range(40)]
        + _rep(duration_s=1.2, depth=1.2)[60:]  # recover to neutral
    )


def test_interruption_at_the_bottom_is_still_one_rep() -> None:
    session = _session(_rest(0.5) + _rep() + _rest(0.8) + _tremor_rep() + _rest(0.8))
    assert len(segment_session(session).reps) == 2


def test_two_fast_reps_are_not_merged_into_one() -> None:
    session = _session(_rest(0.5) + _rep(1.0) + _rest(0.2) + _rep(1.0) + _rest(0.5))
    assert len(segment_session(session).reps) == 2


def _unreturned_motion(settle_at: float = -0.6) -> list[float]:
    """Rep-shaped motion ending below its start."""
    n = 120
    dip = [-0.9 * 0.5 * (1 - math.cos(2 * math.pi * i / n)) for i in range(n // 2)]
    rise = [-0.9 + (-settle_at - 0.9) * -1 * (i / (n // 2)) for i in range(n // 2)]
    return dip + rise


def test_movement_after_a_long_rest_ends_the_set() -> None:
    rolls = _rest(0.5)
    for _ in range(3):
        rolls += _rep() + _rest(0.8)
    rolls += _rest(4.0)  # long rest: the set is over
    rolls += _unreturned_motion()
    rolls += _rest(1.0, level=-0.6)

    result = segment_session(_session(rolls))
    assert len(result.reps) == 3
    assert result.diagnostics.dropped.get(DropReason.AFTER_SET_END, 0) >= 1


def test_a_genuine_rep_after_a_long_pause_is_kept() -> None:
    rolls = _rest(0.5) + _rep() + _rest(4.0) + _rep() + _rest(0.5)
    assert len(segment_session(_session(rolls)).reps) == 2


def test_shallow_twitches_are_not_reps() -> None:
    rolls = _rest(0.5)
    for _ in range(4):
        rolls += _rep(depth=0.05) + _rest(0.5)
    assert segment_session(_session(rolls)).reps == ()


# Derived metrics


def test_phase_times_partition_the_rep() -> None:
    result = segment_session(_set_of(3))
    for rep in result.reps:
        total = result.session[rep.end - 1].t - result.session[rep.start].t
        phases = rep.concentric_time(result.session) + rep.eccentric_time(
            result.session
        )
        assert phases == pytest.approx(total, abs=1e-9)


def test_phase_times_are_never_negative() -> None:
    result = segment_session(_set_of(4))
    for rep in result.reps:
        assert rep.concentric_time(result.session) >= 0.0
        assert rep.eccentric_time(result.session) >= 0.0


def test_range_of_motion_tracks_rep_depth() -> None:
    shallow = segment_session(_session(_rest(0.5) + _rep(depth=0.6) + _rest(0.5)))
    deep = segment_session(_session(_rest(0.5) + _rep(depth=1.4) + _rest(0.5)))
    assert shallow.reps and deep.reps
    assert deep.reps[0].range_of_motion(deep.session) > shallow.reps[0].range_of_motion(
        shallow.session
    )


# Determinism


def test_identical_input_yields_identical_output() -> None:
    session = _set_of(5)
    first = segment_session(session)
    second = segment_session(list(session))
    assert first.reps == second.reps
    assert first.diagnostics == second.diagnostics


def test_input_sequence_is_not_mutated() -> None:
    session = _set_of(3)
    before = list(session)
    segment_session(session)
    assert session == before


# Trust boundary


def test_accepts_a_well_formed_session() -> None:
    session = _set_of(2)
    assert validate_session(session) == tuple(session)


@pytest.mark.parametrize("bad", [float("nan"), float("inf"), float("-inf")])
def test_rejects_non_finite_values(bad: float) -> None:
    session = _set_of(2)
    session[10] = Sample(t=session[10].t, roll=bad, pitch=0.0, yaw=0.0)
    with pytest.raises(InvalidSession) as caught:
        validate_session(session)
    assert caught.value.code == "non_finite_value"


def test_rejects_time_running_backwards() -> None:
    session = _set_of(2)
    session[40] = Sample(t=-1.0, roll=0.0, pitch=0.0, yaw=0.0)
    with pytest.raises(InvalidSession) as caught:
        validate_session(session)
    assert caught.value.code == "non_monotonic_time"


def test_refuses_to_buffer_an_oversized_session() -> None:
    with pytest.raises(InvalidSession) as caught:
        validate_session(_set_of(4), max_samples=100)
    assert caught.value.code == "session_too_long"


def test_oversized_session_is_rejected_without_reading_it_all() -> None:
    consumed = 0

    def rows() -> Iterator[Sample]:
        nonlocal consumed
        for sample in _set_of(20):
            consumed += 1
            yield sample

    with pytest.raises(InvalidSession):
        validate_session(rows(), max_samples=50)
    assert consumed <= 51


# Degenerate input


@pytest.mark.parametrize("rolls", [[], [0.0], [0.0] * 4])
def test_sessions_below_the_minimum_yield_no_reps(rolls: list[float]) -> None:
    assert segment_session(_session(rolls)).reps == ()


def test_a_flat_session_yields_no_reps() -> None:
    assert segment_session(_session(_rest(10.0))).reps == ()


def test_a_monotonic_ramp_yields_no_reps() -> None:
    ramp = [-i / 500.0 for i in range(1000)]
    assert segment_session(_session(ramp)).reps == ()


# Configuration and construction


@pytest.mark.parametrize(
    "overrides",
    [
        {"smoothing_window": 0},
        {"smoothing_window": 2},
        {"min_rep_samples": 2},
        {"range_low_quantile": 0.99, "range_high_quantile": 0.5},
        {"max_anchor_lookahead": 0},
    ],
)
def test_invalid_configuration_is_rejected_at_construction(
    overrides: dict[str, Any],
) -> None:
    with pytest.raises(ValueError):
        SegmentationConfig(**overrides)


def test_segment_rejects_a_valley_outside_its_range() -> None:
    with pytest.raises(ValueError):
        RepSegment(start=10, end=20, valley=25)


def test_raising_the_amplitude_bar_drops_the_lightest_reps() -> None:
    rolls = _rest(0.5) + _rep(depth=1.2) + _rest(0.8) + _rep(depth=0.25) + _rest(0.5)
    session = _session(rolls)
    assert len(segment_session(session).reps) == 2
    strict = SegmentationConfig(min_amplitude_floor=0.6)
    assert len(segment_session(session, strict).reps) == 1


# Diagnostics


def test_candidate_count_is_at_least_the_reps_returned() -> None:
    result = segment_session(_set_of(5))
    assert result.diagnostics.candidates >= len(result.reps)


def test_merge_is_reported() -> None:
    session = _session(_rest(0.5) + _rep() + _rest(0.8) + _tremor_rep() + _rest(0.8))
    assert segment_session(session).diagnostics.merged_oversplits >= 1


def test_diagnostics_accumulate_per_reason() -> None:
    counted = Diagnostics()._with_drop(DropReason.TOO_SHALLOW, 2)
    counted = counted._with_drop(DropReason.TOO_SHALLOW, 3)
    assert counted.dropped == {DropReason.TOO_SHALLOW: 5}


def test_zero_drops_are_not_recorded() -> None:
    assert Diagnostics()._with_drop(DropReason.TOO_SHORT, 0).dropped == {}


# Resting orientation


@pytest.mark.parametrize("neutral", [0.0, -0.15, -0.30, -0.60, -1.00, 0.35])
def test_two_fast_reps_stay_two_at_any_resting_orientation(neutral: float) -> None:
    rolls = (
        _rest(0.5, neutral)
        + _rep(1.0, neutral=neutral)
        + _rest(0.2, neutral)
        + _rep(1.0, neutral=neutral)
        + _rest(0.5, neutral)
    )
    result = segment_session(_session(rolls))
    assert len(result.reps) == 2
    assert result.diagnostics.merged_oversplits == 0


@pytest.mark.parametrize("neutral", [0.0, -0.60, -1.00])
def test_an_over_split_rep_still_merges_at_any_resting_orientation(
    neutral: float,
) -> None:
    rolls = (
        _rest(0.5, neutral)
        + _rep(neutral=neutral)
        + _rest(0.8, neutral)
        + [neutral + v for v in _tremor_rep()]
        + _rest(0.8, neutral)
    )
    result = segment_session(_session(rolls))
    assert len(result.reps) == 2
    assert result.diagnostics.merged_oversplits >= 1


@pytest.mark.parametrize("neutral", [-0.60, 0.35])
def test_counts_a_clean_set_at_an_offset_resting_orientation(neutral: float) -> None:
    rolls = list(_rest(0.5, neutral))
    for _ in range(5):
        rolls += _rep(neutral=neutral) + _rest(0.8, neutral)
    assert len(segment_session(_session(rolls)).reps) == 5


# Entry-point validation


def test_validate_session_returns_a_validated_session() -> None:
    assert isinstance(validate_session(_set_of(2)), ValidatedSession)


def test_segment_session_rechecks_a_validated_session() -> None:
    rows = _set_of(2)
    rows[10] = Sample(t=rows[10].t, roll=float("nan"), pitch=0.0, yaw=0.0)
    marked = ValidatedSession(rows)
    with pytest.raises(InvalidSession) as caught:
        segment_session(marked)
    assert caught.value.code == "non_finite_value"


def test_segment_session_validates_an_unvalidated_sequence() -> None:
    session = _set_of(5)
    assert len(segment_session(session).reps) == 5
    session[300] = Sample(t=session[300].t, roll=float("nan"), pitch=0.0, yaw=0.0)
    with pytest.raises(InvalidSession) as caught:
        segment_session(session)
    assert caught.value.code == "non_finite_value"


def test_segment_session_rejects_time_running_backwards() -> None:
    session = _set_of(3)
    session[40] = Sample(t=-1.0, roll=session[40].roll, pitch=0.0, yaw=0.0)
    with pytest.raises(InvalidSession) as caught:
        segment_session(session)
    assert caught.value.code == "non_monotonic_time"


def test_an_already_validated_session_is_passed_through() -> None:
    validated = validate_session(_set_of(4))
    result = segment_session(validated)
    assert result.session is validated
    assert len(result.reps) == 4


# Parsing untrusted CSV fields


def _rows(count: int = 8, **overrides: str | None) -> list[dict[str, str | None]]:
    rows: list[dict[str, str | None]] = [
        {"t": str(i / SAMPLE_RATE), "roll": "0.1", "pitch": "0.2", "yaw": "0.3"}
        for i in range(count)
    ]
    rows[0].update(overrides)
    return rows


def test_parses_well_formed_rows() -> None:
    parsed = parse_samples(_rows(3))
    assert len(parsed) == 3
    assert parsed[0] == Sample(t=0.0, roll=0.1, pitch=0.2, yaw=0.3)


def test_derives_the_timeline_when_the_collector_wrote_no_timestamp() -> None:
    rows = [{"roll": "0.1", "pitch": "0.2", "yaw": "0.3"} for _ in range(4)]
    parsed = parse_samples(rows, sample_rate_hz=100.0)
    assert [s.t for s in parsed] == [0.0, 0.01, 0.02, 0.03]


@pytest.mark.parametrize("missing", [None, ""])
def test_a_truncated_row_names_the_field_it_lost(missing: str | None) -> None:
    with pytest.raises(InvalidSession) as caught:
        parse_samples(_rows(pitch=missing))
    assert caught.value.code == "missing_field"
    assert "pitch" in str(caught.value)


def test_a_non_numeric_orientation_is_rejected() -> None:
    with pytest.raises(InvalidSession) as caught:
        parse_samples(_rows(roll="n/a"))
    assert caught.value.code == "non_numeric_field"


def test_a_non_numeric_timestamp_is_rejected() -> None:
    with pytest.raises(InvalidSession) as caught:
        parse_samples(_rows(t="--"))
    assert caught.value.code == "non_numeric_field"


def test_a_nan_written_into_the_csv_is_caught_by_validation() -> None:
    with pytest.raises(InvalidSession) as caught:
        parse_samples(_rows(roll="nan"))
    assert caught.value.code == "non_finite_value"


def test_parsed_rows_are_still_checked_for_monotonic_time() -> None:
    rows = _rows(4)
    rows[2]["t"] = "-5.0"
    with pytest.raises(InvalidSession) as caught:
        parse_samples(rows)
    assert caught.value.code == "non_monotonic_time"


@pytest.mark.parametrize("rate", [0.0, -100.0, float("nan"), float("inf")])
def test_an_unusable_sample_rate_is_rejected_before_parsing(rate: float) -> None:
    with pytest.raises(ValueError):
        parse_samples(_rows(2), sample_rate_hz=rate)


def test_a_malformed_row_is_rejected_without_reading_the_rest() -> None:
    consumed = 0

    def rows() -> Iterator[dict[str, str | None]]:
        nonlocal consumed
        for index in range(10_000):
            consumed += 1
            yield {"roll": "bad" if index == 3 else "0.1", "pitch": "0.2", "yaw": "0.3"}

    with pytest.raises(InvalidSession):
        parse_samples(rows())
    assert consumed <= 4


def test_parse_returns_a_validated_session() -> None:
    assert isinstance(parse_samples(_rows(3)), ValidatedSession)


# Extrema


def test_a_plateau_part_way_up_a_climb_is_not_a_peak() -> None:
    from rep_segmentation import _find_extrema

    peaks, valleys = _find_extrema([1.0, 2.0, 3.0, 3.0, 3.0, 4.0, 5.0])
    assert peaks == []
    assert valleys == []


def test_a_flat_topped_peak_yields_exactly_one_anchor() -> None:
    from rep_segmentation import _find_extrema

    peaks, valleys = _find_extrema([0.0, 1.0, 5.0, 5.0, 5.0, 1.0, 0.0])
    assert peaks == [2]
    assert valleys == []


def test_a_flat_bottomed_valley_yields_exactly_one_anchor() -> None:
    from rep_segmentation import _find_extrema

    peaks, valleys = _find_extrema([5.0, 1.0, -2.0, -2.0, 1.0, 5.0])
    assert peaks == []
    assert valleys == [2]


class _CountingIntSequence(Sequence[int]):
    """Sequence with indexed-read accounting."""

    def __init__(self, values: list[int]) -> None:
        self._values = values
        self.reads = 0

    def __len__(self) -> int:
        return len(self._values)

    @overload
    def __getitem__(self, index: int) -> int: ...

    @overload
    def __getitem__(self, index: slice) -> Sequence[int]: ...

    def __getitem__(self, index: int | slice) -> int | Sequence[int]:
        self.reads += 1
        return self._values[index]


def test_anchor_pairing_does_not_rescan_the_complete_valley_list() -> None:
    from rep_segmentation import _pair_anchors

    values = [1.0 if i % 2 == 0 else 0.0 for i in range(4_001)]
    peaks = list(range(0, len(values), 2))
    valleys = _CountingIntSequence(list(range(1, len(values) - 1, 2)))
    segments, rejected = _pair_anchors(
        values,
        peaks,
        valleys,
        min_amplitude=0.5,
        config=SegmentationConfig(),
    )

    assert len(segments) == len(peaks) - 1
    assert rejected == 0
    assert valleys.reads < 10 * len(valleys)


# Diagnostics


def test_every_candidate_is_accounted_for() -> None:
    rolls = _rest(0.5)
    for _ in range(4):
        rolls += _rep() + _rest(0.8)
    rolls += _rep(depth=0.05) + _rest(0.5)  # a twitch, dropped for amplitude
    rolls += _rest(4.0) + _unreturned_motion() + _rest(1.0, level=-0.6)

    result = segment_session(_session(rolls))
    assert result.diagnostics.reconciles_with(len(result.reps))


@pytest.mark.parametrize("count", [1, 3, 5, 10])
def test_the_ledger_balances_on_a_clean_set(count: int) -> None:
    result = segment_session(_set_of(count))
    assert result.diagnostics.reconciles_with(len(result.reps))


def test_amplitude_rejections_are_reported() -> None:
    rolls = _rest(0.5)
    for _ in range(4):
        rolls += _rep(depth=0.05) + _rest(0.5)
    result = segment_session(_session(rolls))
    assert result.reps == ()
    assert result.diagnostics.dropped.get(DropReason.BELOW_AMPLITUDE, 0) >= 1
    assert result.diagnostics.reconciles_with(0)


def test_dropped_counts_cannot_be_mutated_through_the_result() -> None:
    diagnostics = segment_session(_set_of(3)).diagnostics
    with pytest.raises(TypeError):
        diagnostics.dropped[DropReason.TOO_SHORT] = 99  # type: ignore[index]


# Configuration


@pytest.mark.parametrize(
    "name",
    [
        "range_floor_fraction",
        "min_amplitude_fraction",
        "min_amplitude_floor",
        "lead_in_noise_fraction",
        "tighten_margin_fraction",
        "tighten_margin_floor",
        "merge_max_time_gap_s",
        "merge_max_roll_gap",
        "merge_min_valley_depth",
        "min_rep_depth",
        "set_end_rest_gap_s",
        "set_end_drift",
    ],
)
def test_a_negative_threshold_is_rejected(name: str) -> None:
    overrides: dict[str, Any] = {name: -1.0}
    with pytest.raises(ValueError):
        SegmentationConfig(**overrides)


@pytest.mark.parametrize("bad", [float("nan"), float("inf")])
def test_a_non_finite_threshold_is_rejected(bad: float) -> None:
    with pytest.raises(ValueError):
        SegmentationConfig(min_rep_depth=bad)
