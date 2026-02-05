from __future__ import annotations

import pytest
from backend.openclaw_client import _normalize_agent_state


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("waiting", "waiting_for_input"),
        ("needs_input", "waiting_for_input"),
        ("input", "waiting_for_input"),
        ("waiting_for_input", "waiting_for_input"),
        ("done", "done"),
        ("complete", "done"),
        ("completed", "done"),
        ("finished", "done"),
        ("success", "done"),
        ("error", "error"),
        ("failed", "error"),
        ("failure", "error"),
        ("working", "working"),
        ("running", "working"),
        ("", "working"),
        ("unknown", "working"),
        ("something_else", "working"),
    ],
)
def test_normalize_agent_state(raw: str, expected: str) -> None:
    assert _normalize_agent_state(raw) == expected
