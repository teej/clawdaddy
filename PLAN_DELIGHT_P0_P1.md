# ClawDaddy Delight Plan (P0 + P1, no Captain's Log)

## Scope
Implement game-feel inspired delight improvements for ClawDaddy using single-sprite animation, event-driven micro reactions, and rare idle variants. Exclude Captain's Log.

## Goals
- Make acknowledgements feel snappy and satisfying (anticipation + double-bounce).
- Expand idle library with rare, more pronounced variants and subtle baseline motion.
- Add clear cause-and-effect reactions to sub-agent events.
- Add a salute ritual when OpenClaw connects (using the new salute sprite).
- Keep animations readable and non-intrusive.

## Plan (Checklist)
- [ ] Add salute sprite to assets and wire an Image switch for saluting state.
- [ ] Add new animation triggers and styles (ack style, reaction style, salute trigger).
- [ ] Implement action-first acknowledgement (snap + double-bounce) with style based on transcript length.
- [ ] Expand idle system into common + rare pools with delight scarcity.
- [ ] Add micro secondary action / follow-through on large motions.
- [ ] Apply easing pass with consistent timing curves.
- [ ] Add sub-agent cause-effect reactions (start, waiting, done).
- [ ] Validate no regressions in layout and interaction.

## Implementation Notes
- Single sprite only. Use scale/rotation/offset to imply pose and weight.
- Rare idles should be pronounced but infrequent.
- Avoid glow changes unless needed for clarity.
- Keep the acknowledgement quick; it should fire immediately after listening ends.

## Test Strategy
- Manual: trigger 10-20 acknowledgements and verify snap + double-bounce.
- Manual: leave idle for 1-2 minutes and confirm rare variants occur occasionally.
- Manual: trigger sub-agent start/done and observe micro reactions.
- Manual: verify salute appears when OpenClaw connects.
