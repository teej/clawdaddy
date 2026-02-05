from __future__ import annotations

import asyncio
import json
import logging
import random
from contextlib import asynccontextmanager
from typing import Any, Dict

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from backend.openclaw_client import OpenClawClient
from backend.state import StateManager

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
                ack_line = random.choice(ACK_LINES)
                await state_manager.update_clawdaddy(state="speaking", last_response=ack_line)
                await manager.broadcast_state()
                await state_manager.update_clawdaddy(state="thinking")
                await manager.broadcast_state()

                try:
                    await openclaw.send_chat(text)
                except Exception as exc:
                    logger.exception("OpenClaw send failed")
                    await state_manager.update_clawdaddy(
                        state="speaking", last_response=f"Error: {exc}"
                    )
                    await manager.broadcast_state()
                    _spawn_background(_set_clawdaddy_idle())
            elif msg_type == "input_response":
                text = str(data.get("text", "")).strip()
                if text:
                    logger.info("Input response received text_len=%d", len(text))
                    try:
                        await openclaw.send_chat(text)
                    except Exception as exc:
                        logger.exception("OpenClaw send failed (input_response)")
                        await state_manager.update_clawdaddy(
                            state="speaking", last_response=f"Error: {exc}"
                        )
                        await manager.broadcast_state()
                        _spawn_background(_set_clawdaddy_idle())
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception:
        manager.disconnect(websocket)
        raise
