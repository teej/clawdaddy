from __future__ import annotations

import pytest
from backend.state import StateManager, SubAgentState


def _make_agent(id: str, state: str = "working", task: str = "test task") -> SubAgentState:
    return SubAgentState(
        id=id,
        state=state,
        task_description=task,
        updated_at="2026-01-01T00:00:00+00:00",
    )


@pytest.fixture
async def sm() -> StateManager:
    return StateManager()


async def test_initial_state(sm: StateManager) -> None:
    snap = await sm.snapshot()
    assert snap.clawdaddy.state == "idle"
    assert snap.sub_agents == []


async def test_add_single_sub_agent(sm: StateManager) -> None:
    agent = _make_agent("a1")
    await sm.add_sub_agent(agent)
    snap = await sm.snapshot()
    assert len(snap.sub_agents) == 1
    assert snap.sub_agents[0].id == "a1"


async def test_add_multiple_sub_agents(sm: StateManager) -> None:
    await sm.add_sub_agent(_make_agent("a1"))
    await sm.add_sub_agent(_make_agent("a2"))
    await sm.add_sub_agent(_make_agent("a3"))
    snap = await sm.snapshot()
    assert [a.id for a in snap.sub_agents] == ["a1", "a2", "a3"]


async def test_update_sub_agent_state(sm: StateManager) -> None:
    await sm.add_sub_agent(_make_agent("a1"))
    await sm.update_sub_agent("a1", state="done", result="all good")
    snap = await sm.snapshot()
    assert snap.sub_agents[0].state == "done"
    assert snap.sub_agents[0].result == "all good"


async def test_update_nonexistent_is_noop(sm: StateManager) -> None:
    await sm.add_sub_agent(_make_agent("a1"))
    await sm.update_sub_agent("does-not-exist", state="done")
    snap = await sm.snapshot()
    assert len(snap.sub_agents) == 1
    assert snap.sub_agents[0].state == "working"


async def test_remove_sub_agent(sm: StateManager) -> None:
    await sm.add_sub_agent(_make_agent("a1"))
    await sm.add_sub_agent(_make_agent("a2"))
    await sm.remove_sub_agent("a1")
    snap = await sm.snapshot()
    assert [a.id for a in snap.sub_agents] == ["a2"]


async def test_remove_nonexistent_is_noop(sm: StateManager) -> None:
    await sm.add_sub_agent(_make_agent("a1"))
    await sm.remove_sub_agent("does-not-exist")
    snap = await sm.snapshot()
    assert len(snap.sub_agents) == 1


async def test_reset_all_clears_sub_agents(sm: StateManager) -> None:
    await sm.add_sub_agent(_make_agent("a1"))
    await sm.add_sub_agent(_make_agent("a2"))
    await sm.update_clawdaddy(state="thinking")
    await sm.reset_all()
    snap = await sm.snapshot()
    assert snap.sub_agents == []
    assert snap.clawdaddy.state == "idle"


async def test_snapshot_returns_deep_copy(sm: StateManager) -> None:
    await sm.add_sub_agent(_make_agent("a1"))
    snap1 = await sm.snapshot()
    snap1.sub_agents[0].state = "error"
    snap1.sub_agents.append(_make_agent("leaked"))
    snap2 = await sm.snapshot()
    assert snap2.sub_agents[0].state == "working"
    assert len(snap2.sub_agents) == 1
