# OpenClaw Refactor Plan

- [x] Re-read `SPEC.md` and align the refactor with the intended architecture.
- [x] Review current backend (FastAPI + PydanticAI harness) to identify removal points.
- [x] Research OpenClaw gateway WebSocket protocol, events, and required auth/config.
- [x] Implement OpenClaw gateway client (connect, req/res, event handling, reconnection).
- [x] Replace coordinator/sub-agent wiring with OpenClaw message flow + state mapping.
- [x] Update dependencies and remove PydanticAI/Anthropic wiring.
- [x] Update README/env instructions for OpenClaw.
- [x] Quick sanity pass for state/logging paths.
