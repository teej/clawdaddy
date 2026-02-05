from __future__ import annotations

import asyncio
from datetime import datetime
from typing import Optional, Literal

from pydantic import BaseModel, Field


class ClawDaddyState(BaseModel):
    state: Literal["idle", "listening", "speaking", "thinking"] = "idle"
    last_response: str = ""


class SubAgentState(BaseModel):
    id: str
    state: Literal["working", "waiting_for_input", "done", "error"] = "working"
    task_description: str
    question: Optional[str] = None
    result: Optional[str] = None
    error: Optional[str] = None
    updated_at: str


class AppState(BaseModel):
    clawdaddy: ClawDaddyState = Field(default_factory=ClawDaddyState)
    sub_agents: list[SubAgentState] = Field(default_factory=list)


class StateManager:
    def __init__(self) -> None:
        self._state = AppState()
        self._lock = asyncio.Lock()

    async def snapshot(self) -> AppState:
        async with self._lock:
            return self._state.model_copy(deep=True)

    async def update_clawdaddy(self, **kwargs) -> AppState:
        async with self._lock:
            data = self._state.clawdaddy.model_dump()
            data.update(kwargs)
            self._state.clawdaddy = ClawDaddyState(**data)
            return self._state.model_copy(deep=True)

    async def add_sub_agent(self, sub_agent: SubAgentState) -> AppState:
        async with self._lock:
            self._state.sub_agents.append(sub_agent)
            return self._state.model_copy(deep=True)

    async def update_sub_agent(self, sub_agent_id: str, **kwargs) -> AppState:
        async with self._lock:
            updated = []
            for agent in self._state.sub_agents:
                if agent.id == sub_agent_id:
                    data = agent.model_dump()
                    data.update(kwargs)
                    data["updated_at"] = _now_iso()
                    updated.append(SubAgentState(**data))
                else:
                    updated.append(agent)
            self._state.sub_agents = updated
            return self._state.model_copy(deep=True)

    async def remove_sub_agent(self, sub_agent_id: str) -> AppState:
        async with self._lock:
            self._state.sub_agents = [
                agent for agent in self._state.sub_agents if agent.id != sub_agent_id
            ]
            return self._state.model_copy(deep=True)

    async def reset_all(self) -> AppState:
        async with self._lock:
            self._state = AppState()
            return self._state.model_copy(deep=True)


def _now_iso() -> str:
    return datetime.now().isoformat()
