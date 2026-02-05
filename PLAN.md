# Crawdaddy PydanticAI Integration Plan

Goal: Replace the coordinator/sub-agent harness with PydanticAI, keeping the SwiftUI UI while enabling fast tools and up to 20 concurrent sub-agents.

## Checklist
- [x] Add PydanticAI dependency and initial coordinator/sub-agent agent definitions.
- [x] Expand backend state + task manager to support multiple sub-agents (up to 20) and updated WebSocket payloads.
- [x] Update SwiftUI client for new state shape and multi-sub-agent display + input routing.
- [x] Update README for the new backend setup and behavior.

## Notes / Assumptions
- Coordinator is always LLM-driven.
- Tools are split into fast tools (immediate) and sub-agent spawns (async).
- No spoken responses; UI bubbles are the only output channel.
- Anthropic-only for now.
