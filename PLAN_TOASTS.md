# Toast Stack Fix Plan (2026-02-03)

## Goal
Ensure multiple speech bubbles stack visibly (toast-style) without clipping, with a repeatable self-test and UI test.

## Checklist
- [x] Review spec and current layout structure; research SwiftUI scroll/stack patterns.
- [x] Refactor toast layout to a bottom-aligned stack and avoid scroll view height collapse.
- [x] Add layout self-test seeding and a UI test that asserts 4 bubbles are visible.
- [ ] Run UI tests (`xcodebuild test -scheme ClawDaddy`) and adjust if any failures remain.

## Test Strategy (No Human Intervention)
- Launch the app with `CLAWDADDY_LAYOUT_SELFTEST=1` to auto-seed 4 known bubbles.
- UI test `testToastStackShowsMultipleBubbles` asserts:
  - 4 bubble labels exist.
  - Each bubble frame is within the app window bounds.
- Future: add a screenshot assertion if we decide to introduce snapshot testing.
