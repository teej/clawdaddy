from __future__ import annotations

import asyncio
import json
import logging
import os
import random
import shutil
import subprocess
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Awaitable, Callable, Optional

import base64
import hashlib

import websockets
from cryptography.hazmat.primitives import serialization
from websockets import WebSocketClientProtocol
from websockets.exceptions import ConnectionClosed

from backend.state import StateManager, SubAgentState


class OpenClawDiscovery:
    def __init__(
        self, ws_url: Optional[str], api_key: Optional[str], auth_mode: Optional[str]
    ) -> None:
        self.ws_url = ws_url
        self.api_key = api_key
        self.auth_mode = auth_mode


class DeviceIdentity:
    def __init__(
        self,
        device_id: str,
        public_key: str,
        private_key_pem: Optional[str],
        public_key_pem: Optional[str],
    ) -> None:
        self.device_id = device_id
        self.public_key = public_key
        self.private_key_pem = private_key_pem
        self.public_key_pem = public_key_pem


class OpenClawClient:
    def __init__(
        self,
        state_manager: StateManager,
        broadcast_state: Callable[[], Awaitable[None]],
    ) -> None:
        self._state_manager = state_manager
        self._broadcast_state = broadcast_state
        discovered = _discover_openclaw_config()
        self._ws_url = (os.getenv("OPENCLAW_WS_URL") or discovered.ws_url or "").strip()
        self._auth_mode = (
            os.getenv("OPENCLAW_AUTH_MODE") or discovered.auth_mode or "token"
        ).strip()
        self._api_key = (os.getenv("OPENCLAW_API_KEY") or discovered.api_key or "").strip()
        self._chat_method = os.getenv("OPENCLAW_CHAT_METHOD", "chat.send").strip()
        self._idle_delay = float(os.getenv("OPENCLAW_IDLE_DELAY", "1.5"))
        self._debug_events = os.getenv("OPENCLAW_DEBUG_EVENTS", "") == "1"
        self._protocol_min = int(os.getenv("OPENCLAW_PROTOCOL_MIN", "3"))
        self._protocol_max = int(os.getenv("OPENCLAW_PROTOCOL_MAX", "3"))
        self._client_id = "gateway-client"
        self._client_version = os.getenv("OPENCLAW_CLIENT_VERSION", "0.1.0")
        self._client_mode = "backend"
        self._client_instance_id = os.getenv(
            "OPENCLAW_CLIENT_INSTANCE_ID", f"clawdaddy-{os.uname().nodename}"
        )
        self._device_identity = _load_device_identity()
        self._challenge_event = asyncio.Event()
        self._challenge_payload: Optional[dict[str, Any]] = None
        self._logger = logging.getLogger("openclaw")
        if not self._logger.handlers:
            logging.basicConfig(
                level=logging.INFO,
                format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
            )
        self._lock = asyncio.Lock()
        self._pending: dict[str, asyncio.Future] = {}
        self._ws: Optional[WebSocketClientProtocol] = None
        self._recv_task: Optional[asyncio.Task] = None
        self._idle_task: Optional[asyncio.Task] = None
        self._session_key: Optional[str] = None
        self._current_response: str = ""
        self._connected = False

    def _connected_message(self) -> str:
        nautical_lines = [
            "Welcome aboard.",
            "Standing by at the helm.",
            "Awaiting your command.",
            "Where shall we set course?",
            "Ready for orders, Captain.",
            "Deck’s clear and ready.",
            "All systems shipshape.",
            "Set the course, Captain.",
            "At your service, Captain.",
            "What’s the plan, Captain?",
        ]
        return random.choice(nautical_lines)

    async def start(self) -> None:
        if not self._ws_url:
            raise RuntimeError(
                "OpenClaw gateway not detected. Run `openclaw onboard` or `openclaw gateway` "
                "to configure the local gateway."
            )
        self._logger.info(
            "OpenClaw discovery: ws_url=%s auth_mode=%s token=%s",
            self._ws_url,
            self._auth_mode,
            _redact(self._api_key),
        )
        if not self._device_identity:
            raise RuntimeError(
                "OpenClaw device identity not found. Run `openclaw onboard` to create one."
            )
        await self._state_manager.update_clawdaddy(
            state="speaking",
            last_response="Connecting to OpenClaw...",
        )
        await self._broadcast_state()
        await self._connect()

    async def announce_status(self) -> None:
        is_greeting = self._connected
        message = self._connected_message() if is_greeting else "Connecting to OpenClaw..."
        await self._state_manager.update_clawdaddy(
            state="speaking",
            last_response=message,
            is_greeting=is_greeting,
        )
        await self._broadcast_state()

    async def close(self) -> None:
        if self._recv_task:
            self._recv_task.cancel()
            self._recv_task = None
        if self._idle_task:
            self._idle_task.cancel()
            self._idle_task = None
        if self._ws:
            self._logger.info("OpenClaw socket closing")
            await self._ws.close()
            self._ws = None
        self._connected = False

    async def send_chat(self, text: str) -> None:
        if not text.strip():
            return
        await self._ensure_connected()
        if not self._ws or _ws_is_closed(self._ws):
            raise RuntimeError("OpenClaw WebSocket not connected.")
        if not self._session_key:
            raise RuntimeError("OpenClaw sessionKey not available yet.")
        self._current_response = ""
        await self._state_manager.update_clawdaddy(state="thinking")
        await self._broadcast_state()
        payload: dict[str, Any] = {"idempotencyKey": str(uuid.uuid4())}
        payload["sessionKey"] = self._session_key
        payload["message"] = text
        self._logger.info("OpenClaw send %s text_len=%d", self._chat_method, len(text))
        await self._request(self._chat_method, payload)

    async def _connect(self) -> None:
        async with self._lock:
            if self._ws:
                return
            self._logger.info("OpenClaw connecting to %s", self._ws_url)
            self._ws = await websockets.connect(self._ws_url)
            self._recv_task = asyncio.create_task(self._recv_loop())

        self._challenge_event.clear()
        self._challenge_payload = None
        try:
            await asyncio.wait_for(self._challenge_event.wait(), timeout=0.75)
        except asyncio.TimeoutError:
            pass
        try:
            connect_params = self._connect_params(self._challenge_payload)
        except RuntimeError as exc:
            self._logger.error(str(exc))
            return

        try:
            response = await self._request("connect", connect_params)
        except Exception:
            # If connect fails, leave the socket up for retries on next send.
            self._logger.exception("OpenClaw connect failed")
            if self._ws:
                await self._ws.close()
                self._ws = None
            self._connected = False
            return
        self._session_key = _extract_session_key(response) or self._session_key
        self._connected = True
        self._logger.info("OpenClaw connected session=%s", self._session_key or "unknown")
        await self._state_manager.update_clawdaddy(
            state="speaking",
            last_response=self._connected_message(),
            is_greeting=True,
        )
        await self._broadcast_state()
        self._schedule_idle()

    async def _ensure_connected(self) -> None:
        if not self._ws or _ws_is_closed(self._ws):
            self._logger.info("OpenClaw socket not connected, reconnecting")
            await self._connect()

    async def _request(self, method: str, payload: dict[str, Any], timeout: float = 30.0) -> Any:
        if not self._ws:
            raise RuntimeError("OpenClaw WebSocket not connected.")
        req_id = str(uuid.uuid4())
        future = asyncio.get_running_loop().create_future()
        self._pending[req_id] = future
        message = {"type": "req", "id": req_id, "method": method, "params": payload}
        self._logger.debug("OpenClaw req %s id=%s", method, req_id)
        await self._ws.send(json.dumps(message))
        try:
            return await asyncio.wait_for(future, timeout=timeout)
        except asyncio.TimeoutError:
            self._pending.pop(req_id, None)
            raise RuntimeError(f"OpenClaw request {method} timed out after {timeout}s")

    async def _recv_loop(self) -> None:
        assert self._ws is not None
        try:
            async for message in self._ws:
                data = _safe_json(message)
                msg_type = data.get("type")
                if msg_type == "res":
                    await self._handle_response(data)
                elif msg_type == "event":
                    await self._handle_event(data.get("event"), data.get("payload"))
        except ConnectionClosed:
            self._logger.warning("OpenClaw socket closed")
        finally:
            if self._ws:
                await self._ws.close()
            self._ws = None

    async def _handle_response(self, data: dict[str, Any]) -> None:
        req_id = data.get("id")
        if not req_id:
            return
        future = self._pending.pop(req_id, None)
        if not future:
            return
        if data.get("ok") is True:
            self._logger.debug("OpenClaw res id=%s ok=true", req_id)
            future.set_result(data.get("payload"))
        else:
            self._logger.error("OpenClaw res id=%s ok=false error=%s", req_id, data.get("error"))
            future.set_exception(RuntimeError(str(data.get("error") or "OpenClaw error")))

    async def _handle_event(self, name: Optional[str], payload: Any) -> None:
        if self._debug_events:
            print("[openclaw] event:", {"name": name, "payload": payload})
        if name == "connect.challenge" and isinstance(payload, dict):
            self._challenge_payload = payload
            self._challenge_event.set()
            return
        if name:
            self._logger.info("OpenClaw event %s", name)
        if name == "chat":
            await self._handle_chat_event(payload)
        elif name == "agent":
            await self._handle_agent_event(payload)

    async def _handle_chat_event(self, payload: Any) -> None:
        role = _extract_role(payload)
        if role == "user":
            return
        text = _extract_text(payload)
        if not text:
            return
        if _is_delta(payload):
            self._current_response += text
        else:
            self._current_response = text
        self._logger.info("OpenClaw chat role=%s text_len=%d", role or "unknown", len(text))
        await self._state_manager.update_clawdaddy(
            state="speaking",
            last_response=self._current_response,
        )
        await self._broadcast_state()
        self._schedule_idle()

    async def _handle_agent_event(self, payload: Any) -> None:
        if not isinstance(payload, dict):
            return
        agent_id = payload.get("id") or payload.get("agentId") or payload.get("agent_id")
        if not agent_id:
            return
        raw_state = str(payload.get("state") or payload.get("status") or "").lower()
        state = _normalize_agent_state(raw_state)
        task_description = payload.get("task") or payload.get("description") or "OpenClaw task"
        question = payload.get("question")
        result = payload.get("result") or payload.get("output")
        error = payload.get("error")

        snapshot = await self._state_manager.snapshot()
        if any(agent.id == agent_id for agent in snapshot.sub_agents):
            await self._state_manager.update_sub_agent(
                agent_id,
                state=state,
                task_description=task_description,
                question=question,
                result=result,
                error=error,
            )
        else:
            await self._state_manager.add_sub_agent(
                SubAgentState(
                    id=str(agent_id),
                    state=state,
                    task_description=str(task_description),
                    question=question,
                    result=result,
                    error=error,
                    updated_at=_now_iso(),
                )
            )
        self._logger.info(
            "OpenClaw agent id=%s state=%s task=%s",
            agent_id,
            state,
            str(task_description),
        )
        await self._broadcast_state()

    def _connect_params(
        self,
        challenge: Optional[dict[str, Any]] = None,
    ) -> dict[str, Any]:
        params: dict[str, Any] = {
            "minProtocol": self._protocol_min,
            "maxProtocol": self._protocol_max,
            "client": {
                "id": self._client_id,
                "instanceId": self._client_instance_id,
                "version": self._client_version,
                "platform": "darwin",
                "mode": self._client_mode,
            },
            "caps": [],
            "role": "operator",
            "scopes": ["operator.admin"],
            "locale": "en-US",
            "userAgent": f"openclaw-cli/{self._client_version}",
        }
        device_params = _build_device_params(
            self._device_identity,
            challenge,
            token=self._api_key if self._api_key else None,
            client_id=self._client_id,
            client_mode=self._client_mode,
            role="operator",
            scopes=["operator.admin"],
        )
        if device_params:
            params["device"] = device_params
        if self._api_key:
            if self._auth_mode == "password":
                params["auth"] = {"password": self._api_key}
            else:
                params["auth"] = {"token": self._api_key}
        return params

    def _schedule_idle(self) -> None:
        if self._idle_task:
            self._idle_task.cancel()
        self._idle_task = asyncio.create_task(self._set_idle())

    async def _set_idle(self) -> None:
        try:
            await asyncio.sleep(self._idle_delay)
        except asyncio.CancelledError:
            return
        await self._state_manager.update_clawdaddy(state="idle")
        await self._broadcast_state()


def _safe_json(message: str) -> dict[str, Any]:
    try:
        data = json.loads(message)
        if isinstance(data, dict):
            return data
    except json.JSONDecodeError:
        pass
    return {}


def _extract_session_key(payload: Any) -> Optional[str]:
    if isinstance(payload, dict):
        direct = payload.get("sessionKey") or payload.get("session_key")
        if isinstance(direct, str) and direct:
            return direct
        snapshot = payload.get("snapshot")
        if isinstance(snapshot, dict):
            defaults = snapshot.get("sessionDefaults")
            if isinstance(defaults, dict):
                key = defaults.get("mainSessionKey")
                if isinstance(key, str) and key:
                    return key
    return None


def _extract_role(payload: Any) -> Optional[str]:
    if isinstance(payload, dict):
        role = payload.get("role")
        if role:
            return str(role)
        message = payload.get("message")
        if isinstance(message, dict) and message.get("role"):
            return str(message["role"])
    return None


def _extract_text(payload: Any) -> str:
    if isinstance(payload, str):
        return payload
    if isinstance(payload, dict):
        for key in ("text", "message", "content", "delta", "result", "output"):
            if key not in payload:
                continue
            value = payload.get(key)
            text = _extract_text(value)
            if text:
                return text
    if isinstance(payload, list):
        parts = []
        for item in payload:
            if isinstance(item, dict) and item.get("type") == "text" and "text" in item:
                parts.append(str(item["text"]))
            elif isinstance(item, str):
                parts.append(item)
        return "".join(parts)
    return ""


def _is_delta(payload: Any) -> bool:
    if isinstance(payload, dict):
        if payload.get("type") in {"delta", "partial"}:
            return True
        if "delta" in payload:
            return True
    return False


def _normalize_agent_state(raw_state: str) -> str:
    if raw_state in {"waiting", "needs_input", "input", "waiting_for_input"}:
        return "waiting_for_input"
    if raw_state in {"done", "complete", "completed", "finished", "success"}:
        return "done"
    if raw_state in {"error", "failed", "failure"}:
        return "error"
    return "working"


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _discover_openclaw_config() -> OpenClawDiscovery:
    ws_url = None
    api_key = None
    auth_mode = None

    if shutil.which("openclaw"):
        ws_url, api_key, auth_mode = _discover_via_cli()
    if not ws_url or api_key is None:
        file_ws, file_key, file_mode = _discover_via_file()
        ws_url = ws_url or file_ws
        api_key = api_key or file_key
        auth_mode = auth_mode or file_mode

    return OpenClawDiscovery(ws_url, api_key, auth_mode)


def _discover_via_cli() -> tuple[Optional[str], Optional[str], Optional[str]]:
    remote_url = _cli_get("gateway.remote.url")
    remote_token = _cli_get("gateway.remote.token")
    if isinstance(remote_url, str) and remote_url:
        return remote_url, remote_token if isinstance(remote_token, str) else None, "token"

    port = _cli_get("gateway.port")
    auth_mode = _cli_get("gateway.auth.mode")
    token = _cli_get("gateway.auth.token") if auth_mode in {None, "token"} else None
    password = _cli_get("gateway.auth.password") if auth_mode == "password" else None

    ws_url = f"ws://127.0.0.1:{port}" if port else None

    api_key = None
    if auth_mode == "password":
        api_key = password if isinstance(password, str) else None
    else:
        api_key = token if isinstance(token, str) else None

    return ws_url, api_key, auth_mode if isinstance(auth_mode, str) else None


def _discover_via_file() -> tuple[Optional[str], Optional[str], Optional[str]]:
    config_path = os.getenv("OPENCLAW_CONFIG_PATH")
    if not config_path:
        state_dir = os.getenv("OPENCLAW_STATE_DIR", os.path.expanduser("~/.openclaw"))
        config_path = os.path.join(state_dir, "openclaw.json")

    try:
        with open(config_path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception:
        return None, None, None

    gateway = data.get("gateway", {}) if isinstance(data, dict) else {}
    remote = gateway.get("remote", {}) if isinstance(gateway, dict) else {}
    if isinstance(remote, dict):
        remote_url = remote.get("url")
        remote_token = remote.get("token")
        if isinstance(remote_url, str) and remote_url:
            return remote_url, remote_token if isinstance(remote_token, str) else None, "token"

    port = gateway.get("port")
    auth = gateway.get("auth", {}) if isinstance(gateway, dict) else {}
    auth_mode = auth.get("mode")
    token = auth.get("token") if auth_mode in {None, "token"} else None
    password = auth.get("password") if auth_mode == "password" else None

    ws_url = f"ws://127.0.0.1:{port}" if port else None

    if auth_mode == "password":
        api_key = password if isinstance(password, str) else None
    else:
        api_key = token if isinstance(token, str) else None

    return ws_url, api_key, auth_mode if isinstance(auth_mode, str) else None


def _cli_get(path: str) -> Optional[Any]:
    try:
        result = subprocess.run(
            ["openclaw", "config", "get", path, "--json"],
            capture_output=True,
            text=True,
            check=False,
        )
    except Exception:
        return None
    if result.returncode != 0:
        return None
    value = result.stdout.strip()
    if not value:
        return None
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return value


def _load_device_identity() -> Optional[DeviceIdentity]:
    identity_path = os.getenv("OPENCLAW_DEVICE_PATH")
    if not identity_path:
        state_dir = os.getenv("OPENCLAW_STATE_DIR", os.path.expanduser("~/.openclaw"))
        identity_path = os.path.join(state_dir, "identity", "device.json")
    try:
        with open(identity_path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception:
        return None
    if not isinstance(data, dict):
        return None
    device_id = data.get("deviceId") or data.get("id")
    public_key_pem = data.get("publicKeyPem") or data.get("publicKey")
    private_key_pem = data.get("privateKeyPem")
    if not device_id or not public_key_pem or not private_key_pem:
        return None
    public_key_raw = _public_key_raw_base64url_from_pem(public_key_pem)
    if not public_key_raw:
        return None
    derived_id = _derive_device_id(public_key_raw)
    if derived_id:
        device_id = derived_id
    return DeviceIdentity(str(device_id), public_key_raw, private_key_pem, public_key_pem)


def _build_device_params(
    identity: Optional[DeviceIdentity],
    challenge: Optional[dict[str, Any]],
    *,
    token: Optional[str],
    client_id: str,
    client_mode: str,
    role: str,
    scopes: list[str],
) -> Optional[dict[str, Any]]:
    if not identity:
        return None
    if not identity.private_key_pem:
        raise RuntimeError("OpenClaw device signing requires a private key.")

    signed_at = int(time.time() * 1000)
    nonce = None
    if challenge and isinstance(challenge.get("nonce"), str):
        nonce = str(challenge.get("nonce"))

    payload = _build_device_auth_payload(
        device_id=identity.device_id,
        client_id=client_id,
        client_mode=client_mode,
        role=role,
        scopes=scopes,
        signed_at_ms=signed_at,
        token=token,
        nonce=nonce,
    )
    signature = _sign_payload(identity.private_key_pem, payload)
    if not signature:
        raise RuntimeError("Failed to sign OpenClaw payload. Install cryptography.")
    params = {
        "id": identity.device_id,
        "publicKey": identity.public_key,
        "signature": signature,
        "signedAt": signed_at,
    }
    if nonce:
        params["nonce"] = nonce
    return params


def _public_key_raw_base64url_from_pem(pem: str) -> Optional[str]:
    try:
        public_key = serialization.load_pem_public_key(pem.encode("utf-8"))
        raw = public_key.public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
        return _base64url_encode(raw)
    except Exception:
        return None


def _derive_device_id(public_key_base64url: str) -> Optional[str]:
    try:
        raw = _base64url_decode(public_key_base64url)
        return hashlib.sha256(raw).hexdigest()
    except Exception:
        return None


def _build_device_auth_payload(
    *,
    device_id: str,
    client_id: str,
    client_mode: str,
    role: str,
    scopes: list[str],
    signed_at_ms: int,
    token: Optional[str],
    nonce: Optional[str],
) -> str:
    version = "v2" if nonce else "v1"
    scopes_joined = ",".join(scopes)
    token_value = token or ""
    base = [
        version,
        device_id,
        client_id,
        client_mode,
        role,
        scopes_joined,
        str(signed_at_ms),
        token_value,
    ]
    if version == "v2":
        base.append(nonce or "")
    return "|".join(base)


def _sign_payload(private_key_pem: str, payload: str) -> Optional[str]:
    try:
        key = serialization.load_pem_private_key(
            private_key_pem.encode("utf-8"), password=None
        )
        if not hasattr(key, "sign"):
            return None
        signature = key.sign(payload.encode("utf-8"))
        return _base64url_encode(signature)
    except Exception:
        return None


def _base64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("utf-8").rstrip("=")


def _base64url_decode(text: str) -> bytes:
    padding = "=" * ((4 - len(text) % 4) % 4)
    return base64.urlsafe_b64decode(text + padding)


def _redact(value: str) -> str:
    if not value:
        return "none"
    if len(value) <= 6:
        return "***"
    return f"{value[:2]}***{value[-2:]}"


def _ws_is_closed(ws: Any) -> bool:
    if ws is None:
        return True
    closed_attr = getattr(ws, "closed", None)
    if isinstance(closed_attr, bool):
        return closed_attr
    try:
        from websockets.protocol import State  # type: ignore

        state = getattr(ws, "state", None)
        return state in (State.CLOSED, State.CLOSING)
    except Exception:
        state = getattr(ws, "state", None)
        if hasattr(state, "name"):
            return state.name in {"CLOSED", "CLOSING"}
    return False
