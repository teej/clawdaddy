# Swift Gateway Migration Plan

## Goal

Remove the Python backend and run ClawDaddy as a single macOS app that talks directly to the OpenClaw gateway.

## Decision

Proceed with a full Swift migration. Keep no Python runtime dependency in the shipped app.

## Scope

Port these backend responsibilities into Swift:

1. Gateway config discovery (`OPENCLAW_*`, CLI config, file config fallback).
2. OpenClaw websocket lifecycle and JSON-RPC request/response handling.
3. Session connect handshake and session key extraction.
4. Chat and agent event handling into app state.
5. Local orchestration behavior currently in Python:
   - ack line selection
   - thinking/speaking/idle transitions
   - reunion detection
   - sub-agent state updates and cleanup

## Target Architecture

1. `WebSocketClient` (SwiftUI-facing facade)
   - keeps current public API:
   - `connect()`
   - `disconnect()`
   - `sendTranscript(_:)`
   - `sendInputResponse(_:subAgentId:)`
   - `@Published var appState`
2. `OpenClawGatewayClient` internals
   - direct gateway websocket transport
   - request correlation by id
   - event router for `chat` and `agent`
3. `OpenClawConfigDiscovery`
   - env -> CLI (`openclaw config get`) -> file (`~/.openclaw/openclaw.json`)

## Compatibility Guardrails

1. Preserve `AppState` shape used by existing SwiftUI views.
2. Preserve behavior of `is_greeting` and `is_reunion`.
3. Preserve normalized sub-agent states:
   - `working`
   - `waiting_for_input`
   - `done`
   - `error`

## Risk Areas

1. Gateway auth variants (token/password/device challenge signature).
2. Event payload drift across gateway versions.
3. Reconnect/session recovery behavior.
4. UI test automation prompts unrelated to migration logic.

## Test Strategy

1. `just check` for Swift parse + macOS unit tests.
2. `just test-macos` for macOS unit tests.
3. Manual smoke test with real OpenClaw:
   - start app
   - verify greeting
   - send transcript
   - verify speaking/thinking/idle transitions
   - verify sub-agent bubble update flow

## Rollout Plan

1. Phase 1: Implement direct gateway client in Swift and keep UI API unchanged.
2. Phase 2: Validate parity with real gateway sessions.
3. Phase 3: Remove Python backend codepaths and docs. (in progress)
4. Phase 4: Update release packaging to app-only. (in progress)

## Deletion Checklist (when parity is confirmed)

1. Remove `backend/` runtime usage from release flow. (done)
2. Update `README.md` to app-only startup instructions. (done)
3. Remove backend launch requirements from `TESTING.md`. (done)
4. Remove Python backend recipes from `justfile` if no longer needed. (done)
5. Remove obsolete backend source tree and Python lockfile from repo. (pending)
