# ClawDaddy Testing Runbook

## 1. Backend Unit Tests (pytest)

```bash
uv run --extra test pytest backend/tests/ -v
```

All tests should pass. Covers:
- `test_state.py` — StateManager sub-agent lifecycle (add, update, remove, reset, snapshot isolation)
- `test_openclaw_helpers.py` — `_normalize_agent_state` synonym mapping

## 2. Debug Injection (curl)

Start the backend with debug mode enabled:

```bash
DEBUG_INJECT=1 uv run uvicorn backend.main:app --reload
```

Create a working sub-agent:

```bash
curl -X POST http://localhost:8000/debug/sub-agent \
  -H 'Content-Type: application/json' \
  -d '{"id": "test-1", "state": "working", "task_description": "Scouting the reef"}'
```

Transition to waiting_for_input:

```bash
curl -X POST http://localhost:8000/debug/sub-agent \
  -H 'Content-Type: application/json' \
  -d '{"id": "test-1", "state": "waiting_for_input", "question": "Which reef?"}'
```

Transition to done (auto-cleanup after 8s):

```bash
curl -X POST http://localhost:8000/debug/sub-agent \
  -H 'Content-Type: application/json' \
  -d '{"id": "test-1", "state": "done", "result": "Found the treasure!"}'
```

Manual removal:

```bash
curl -X POST http://localhost:8000/debug/sub-agent/test-1/remove
```

Verify endpoints are hidden without `DEBUG_INJECT=1`:

```bash
# Without DEBUG_INJECT, should return 404
uv run uvicorn backend.main:app --reload &
curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8000/debug/sub-agent \
  -H 'Content-Type: application/json' -d '{"id": "x"}'
# Expected: 404
```

## 3. Sub-Agent Selftest (SwiftUI)

Launch the app with the selftest environment variable:

```bash
CLAWDADDY_SUBAGENT_SELFTEST=1 open ClawDaddy/build/Build/Products/Debug/ClawDaddy.app
```

Or set the env var in Xcode scheme > Run > Arguments > Environment Variables.

Expected:
- 4 lobster emojis in the bottom row
- 3 speech bubbles: question ("What bait should I use?"), result ("Found 3 treasure chests!"), error ("Lost the anchor!")
- No bubble for the working agent (working agents don't produce messages)

## 4. UI Tests (xcodebuild)

```bash
xcodebuild test \
  -project ClawDaddy/ClawDaddy.xcodeproj \
  -scheme ClawDaddy \
  -destination 'platform=macOS' \
  -only-testing:ClawDaddyUITests
```

Key tests:
- `testSubAgentSelfTestShowsEmojis` — verifies 4 lobster emojis appear
- `testSubAgentSelfTestShowsBubbles` — verifies question, result, and error bubbles
- `testToastStackShowsMultipleBubbles` — existing layout selftest (4 SELFTEST bubbles)
