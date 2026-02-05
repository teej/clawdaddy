from __future__ import annotations

import asyncio
import json
import logging
import os
import random
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any, Dict

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect

from backend.openclaw_client import OpenClawClient
from backend.state import StateManager, SubAgentState

logger = logging.getLogger("clawdaddy")
if not logger.handlers:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

state_manager = StateManager()

ACK_LINES = [
    "Aye aye, cap'n!",
    "Aye, matey.",
    "On it, skipper.",
    "Full steam ahead.",
    "Setting course.",
    "Charting it now.",
    "Anchors aweigh.",
    "Hoisting sails.",
    "Sounding the depths.",
    "All hands on it.",
    "On the double.",
    "Claws to work.",
    "By the tide.",
    "By the brine.",
    "Reefing it now.",
    "Lines are cast.",
    "Trim the sails.",
    "Taking the helm.",
    "Scouting the waters.",
    "Netting it now.",
    "Hauling it in.",
    "Casting off.",
    "Aye, aye.",
    "Right away, mate.",
    "On the case, cap'n.",
    "Ready and seaworthy.",
    "Steady as she goes.",
    "No time to flounder.",
    "Consider it in the log.",
    "Hook, line, and sinker.",
]

SHORT_ACK_LINES = [
    "On it.",
    "Aye.",
    "Done deal.",
    "Aye aye.",
    "Right away.",
]

LONG_ACK_LINES = [
    "That's a tall order — let me reef the sails.",
    "Lot of ground to cover. Setting course.",
    "Big voyage ahead. Charting the route.",
    "Heavy cargo, cap'n. Loading it up.",
    "Long haul — all hands on deck.",
]

REUNION_ACK_LINES = [
    "There ye are, cap'n!",
    "Thought ye'd walked the plank!",
    "The crew was getting restless!",
    "Cap'n returns! All hands to stations!",
    "Back on deck! The sea missed ye!",
]

ERROR_LINES = [
    "Hit a reef there, cap'n. Give me a moment.",
    "Lost the signal. The sea's rough today.",
    "Ran aground on that one. Trying another tack.",
    "The current pulled us off course. Stand by.",
    "Something's fouled in the rigging. Hold tight.",
]


def _pick_ack_line(text: str, is_reunion: bool) -> str:
    if is_reunion:
        return random.choice(REUNION_ACK_LINES)
    word_count = len(text.split())
    if word_count <= 5:
        return random.choice(SHORT_ACK_LINES)
    if word_count > 25:
        return random.choice(LONG_ACK_LINES)
    return random.choice(ACK_LINES)


class ConnectionManager:
    def __init__(self) -> None:
        self._connections: set[WebSocket] = set()

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        is_first = len(self._connections) == 0
        self._connections.add(websocket)
        if is_first:
            await state_manager.reset_all()
        await self.broadcast_state()

    def disconnect(self, websocket: WebSocket) -> None:
        self._connections.discard(websocket)

    async def broadcast_state(self) -> None:
        for websocket in list(self._connections):
            try:
                await self._send_state(websocket)
            except Exception:
                self.disconnect(websocket)

    async def _send_state(self, websocket: WebSocket) -> None:
        state = await state_manager.snapshot()
        payload = {"type": "state", "state": state.model_dump()}
        await websocket.send_text(json.dumps(payload))


def _parse_message(text: str) -> Dict[str, Any]:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {}


manager = ConnectionManager()
openclaw: OpenClawClient | None = None
_background_tasks: set[asyncio.Task] = set()


def _spawn_background(coro) -> None:
    task = asyncio.create_task(coro)
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)


async def _set_clawdaddy_idle(delay_seconds: float = 1.5) -> None:
    await asyncio.sleep(delay_seconds)
    await state_manager.update_clawdaddy(state="idle")
    await manager.broadcast_state()


@asynccontextmanager
async def lifespan(app):
    global openclaw
    openclaw = OpenClawClient(state_manager, manager.broadcast_state)
    await openclaw.start()
    yield
    await openclaw.close()


app = FastAPI(lifespan=lifespan)


@app.get("/health")
async def health() -> Dict[str, str]:
    return {"status": "ok"}


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    await manager.connect(websocket)
    assert openclaw is not None
    await openclaw.announce_status()
    try:
        while True:
            message = await websocket.receive_text()
            data = _parse_message(message)
            msg_type = data.get("type")
            if msg_type == "transcript":
                text = str(data.get("text", "")).strip()
                if not text:
                    continue
                logger.info("Transcript received text_len=%d", len(text))
                is_reunion = openclaw.check_reunion()
                ack_line = _pick_ack_line(text, is_reunion)
                await state_manager.update_clawdaddy(
                    state="speaking",
                    last_response=ack_line,
                    is_greeting=False,
                    is_reunion=is_reunion,
                )
                await manager.broadcast_state()
                await state_manager.update_clawdaddy(state="thinking")
                await manager.broadcast_state()

                try:
                    await openclaw.send_chat(text)
                except Exception as exc:
                    logger.exception("OpenClaw send failed")
                    await state_manager.update_clawdaddy(
                        state="speaking",
                        last_response=random.choice(ERROR_LINES),
                    )
                    await manager.broadcast_state()
                    _spawn_background(_set_clawdaddy_idle())
            elif msg_type == "input_response":
                text = str(data.get("text", "")).strip()
                sub_agent_id = data.get("sub_agent_id")
                if text:
                    logger.info(
                        "Input response received text_len=%d sub_agent_id=%s",
                        len(text),
                        sub_agent_id,
                    )
                    if sub_agent_id:
                        await state_manager.update_sub_agent(
                            sub_agent_id, state="working", question=None
                        )
                        await manager.broadcast_state()
                    try:
                        await openclaw.send_chat(text)
                    except Exception as exc:
                        logger.exception("OpenClaw send failed (input_response)")
                        await state_manager.update_clawdaddy(
                            state="speaking",
                            last_response=random.choice(ERROR_LINES),
                        )
                        await manager.broadcast_state()
                        _spawn_background(_set_clawdaddy_idle())
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception:
        manager.disconnect(websocket)
        raise


def _debug_enabled() -> bool:
    return os.getenv("DEBUG_INJECT", "") == "1"


@app.post("/debug/sub-agent")
async def debug_create_sub_agent(body: Dict[str, Any]) -> Dict[str, Any]:
    if not _debug_enabled():
        raise HTTPException(status_code=404, detail="Not found")
    agent_id = body.get("id") or body.get("agent_id")
    if not agent_id:
        raise HTTPException(status_code=400, detail="id is required")
    state = body.get("state", "working")
    task_description = body.get("task_description", "debug task")
    question = body.get("question")
    result = body.get("result")
    error = body.get("error")

    snapshot = await state_manager.snapshot()
    if any(a.id == agent_id for a in snapshot.sub_agents):
        await state_manager.update_sub_agent(
            agent_id,
            state=state,
            task_description=task_description,
            question=question,
            result=result,
            error=error,
        )
    else:
        await state_manager.add_sub_agent(
            SubAgentState(
                id=str(agent_id),
                state=state,
                task_description=str(task_description),
                question=question,
                result=result,
                error=error,
                updated_at=datetime.now(timezone.utc).isoformat(),
            )
        )
    await manager.broadcast_state()
    return {"ok": True, "agent_id": agent_id, "state": state}


@app.post("/debug/sub-agent/{agent_id}/remove")
async def debug_remove_sub_agent(agent_id: str) -> Dict[str, Any]:
    if not _debug_enabled():
        raise HTTPException(status_code=404, detail="Not found")
    await state_manager.remove_sub_agent(agent_id)
    await manager.broadcast_state()
    return {"ok": True, "agent_id": agent_id, "removed": True}
