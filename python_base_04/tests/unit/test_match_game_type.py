"""Match rules variant normalization for update-game-stats and leaderboards."""

from core.modules.dutch_game.api_endpoints import (
    _normalize_leaderboard_period_arg,
    _normalize_match_game_type,
    _parse_leaderboard_game_type_arg,
    _period_wins_ended_at_match,
    _period_wins_match_filter,
)
from datetime import datetime, timezone


def test_normalize_match_game_type_classic():
    assert _normalize_match_game_type({"game_type": "classic"}) == "classic"


def test_normalize_match_game_type_clear_and_collect():
    assert _normalize_match_game_type({"game_type": "clear_and_collect"}) == "clear_and_collect"
    assert _normalize_match_game_type({"isClearAndCollect": True}) == "clear_and_collect"


def test_normalize_match_game_type_default():
    assert _normalize_match_game_type({}) == "classic"


def test_parse_leaderboard_game_type_arg():
    assert _parse_leaderboard_game_type_arg("") is None
    assert _parse_leaderboard_game_type_arg("all") is None
    assert _parse_leaderboard_game_type_arg("classic") == "classic"
    assert _parse_leaderboard_game_type_arg("cc") == "clear_and_collect"
    assert _parse_leaderboard_game_type_arg("invalid") == "__invalid__"


def test_period_wins_ended_at_match_classic_includes_legacy():
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)
    end = datetime(2026, 2, 1, tzinfo=timezone.utc)
    clause = _period_wins_ended_at_match(start, end, "classic")
    assert "$and" in clause
    parts = clause["$and"]
    assert any("ended_at" in p for p in parts)
    assert any("$or" in p for p in parts)


def test_period_wins_ended_at_match_clear_and_collect():
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)
    end = datetime(2026, 2, 1, tzinfo=timezone.utc)
    clause = _period_wins_ended_at_match(start, end, "clear_and_collect")
    assert "$and" in clause
    assert {"game_type": "clear_and_collect"} in clause["$and"]


def test_period_wins_match_filter_all_time():
    clause = _period_wins_match_filter(None, start=None, end=None)
    assert clause == {}


def test_normalize_leaderboard_period_arg():
    assert _normalize_leaderboard_period_arg("all_time") == "all_time"
    assert _normalize_leaderboard_period_arg("all-time") == "all_time"
    assert _normalize_leaderboard_period_arg("monthly") == "monthly"
    assert _normalize_leaderboard_period_arg("weekly") is None
