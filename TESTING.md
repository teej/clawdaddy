# ClawDaddy Testing Runbook

## 1. Swift Checks

```bash
just check
```

This runs:
- Swift parse check
- macOS unit tests (`ClawDaddyTests`)

## 2. macOS Unit Tests

```bash
just test-macos
```

## 3. UI Tests (interactive environment)

```bash
just test-macos-ui
```

## 4. Manual Gateway Smoke Test

Ensure OpenClaw has been onboarded on the host:

```bash
openclaw onboard
```

Launch the app:

```bash
open /tmp/crawdaddy-derived/Build/Products/Debug/ClawDaddy.app
```

Expected:
- Console logs include `OpenClaw discovery summary` and `OpenClaw identity summary`
- PTT can send a transcript and receive a response
- Avatar transitions speaking -> thinking -> idle

## 5. Sub-Agent Selftest (SwiftUI)

```bash
CLAWDADDY_SUBAGENT_SELFTEST=1 open /tmp/crawdaddy-derived/Build/Products/Debug/ClawDaddy.app
```

Key tests:
- `testSubAgentSelfTestShowsEmojis` — verifies 4 lobster emojis appear
- `testSubAgentSelfTestShowsBubbles` — verifies question, result, and error bubbles
- `testToastStackShowsMultipleBubbles` — existing layout selftest (4 SELFTEST bubbles)
