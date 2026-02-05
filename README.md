# Crawdaddy

Audio-first agent harness prototype (macOS SwiftUI + Python FastAPI).

## Backend (uv)

```bash
uv sync
uv run uvicorn backend.main:app --reload --port 8000
```

The backend proxies transcripts to OpenClaw's gateway WebSocket; OpenClaw handles sub-agents.

The backend auto-discovers the gateway URL + auth token from the OpenClaw CLI/config
(`openclaw config get gateway.*`). No `.env` setup is required.

Optional overrides (environment variables, not `.env`):

```
OPENCLAW_WS_URL=ws://127.0.0.1:18789
OPENCLAW_API_KEY=token_here
OPENCLAW_AUTH_MODE=token  # or "password"
OPENCLAW_CHAT_METHOD=chat.send
OPENCLAW_CHAT_MESSAGE_FORMAT=text  # or "message"
OPENCLAW_IDLE_DELAY=1.5
OPENCLAW_DEBUG_EVENTS=0
```

## macOS App

1. Open `Crawdaddy/Crawdaddy.xcodeproj` in Xcode.
2. Add usage descriptions to Info.plist:
   - `NSSpeechRecognitionUsageDescription`
   - `NSMicrophoneUsageDescription`
3. Run the app. Hold the left Command (⌘) key to talk.

Notes:
- The push-to-talk key monitor is local, so the window needs focus.
- The WebSocket URL is hardcoded to `ws://127.0.0.1:8000/ws` in `Crawdaddy/Crawdaddy/WebSocketClient.swift`.
