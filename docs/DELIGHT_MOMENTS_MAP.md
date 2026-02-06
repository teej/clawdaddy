# Delight Moments Map

## Goal

Create memorable, intentional character moments without adding instrumentation and without requiring new animation frames from engineering.

Constraints:

- Use existing sprites/animations today.
- If new frames are provided later, plug them into this same choreography map.
- Validate delight through short manual review loops.

## Delight Review Loop

Use this loop for each moment before moving to the next:

1. Define one moment and its micro-rubric.
2. Implement only that moment.
3. Run 10-15 manual interactions.
4. Score each pass with the rubric (`pass`/`fail` + one sentence).
5. Tune timing/sequence and repeat.

Micro-rubric (max 3 checks):

- `intentional`: reads as a purposeful character beat.
- `payoff`: has a clear anticipation -> release feel.
- `replayable`: you want to trigger it again.

## State Moments

### `idle`

Intent:

- Feel alive without stealing attention.

Choreography (current assets):

- Existing idle variants remain primary.
- Keep rare variants rare enough to stay surprising.

Pass criteria:

- Character feels present in background.
- No repetitive loop becomes obvious in under 30 seconds.

### `listening`

Intent:

- “I heard you” should register instantly.

Choreography (current assets):

- Existing listen squash + glow.
- Keep response snappy and high-contrast.

Pass criteria:

- Recognition feels immediate.
- The start of listening feels inviting, not aggressive.

### `thinking`

Intent:

- Build anticipation, not dead air.

Choreography (current assets):

- Existing thinking sway + occasional `DaddyThinking` flash.
- Hero transition beat enters from listening with a quick `perk` reaction.

Pass criteria:

- Thinking feels active and curious.
- Transition from listening feels like a deliberate handoff.

### `speaking`

Intent:

- Deliver with personality.

Choreography (current assets):

- Existing talk-cycle mouth movement.
- Hero transition beat enters from thinking with a quick `nod` emote.

Pass criteria:

- Start of speech has a “here we go” moment.
- Talking motion supports delivery without visual noise.

### `celebrating`

Intent:

- Reward success with charm and brief spectacle.

Choreography (current assets):

- Keep `dance`/`excited` as short punchy rewards.
- Avoid chaining too many large movements in normal flow.

Pass criteria:

- Celebration feels earned.
- It ends before becoming distracting.

### `error-recovery`

Intent:

- Keep the character likable when things go wrong.

Choreography (current assets):

- Use alert/surprised beats sparingly.
- Favor playful recovery tone over alarm.

Pass criteria:

- Error state is acknowledged without killing mood.
- Return to neutral is smooth and quick.

## Hero Moment (Implemented First)

Moment:

- `listening -> thinking -> speaking`

Current choreography:

- On `listening -> thinking`: trigger `reaction(.perk)`.
- On `thinking -> speaking`: trigger `emote(.nod)`.
- Cooldown prevents spam during rapid state flaps.

Why this first:

- It is the most frequent conversational arc.
- It adds anticipation and payoff without new art.
- It is easy to tune quickly via timing and transition choice.

## Manual Session Checklist (No Instrumentation)

Run this after each iteration:

1. Perform 10-15 normal voice interactions.
2. Watch only the transition arc (`listening -> thinking -> speaking`).
3. Mark each interaction as:
- `A`: delightful and intentional.
- `B`: acceptable but flat.
- `C`: distracting or awkward.
4. Note one short sentence for each `B`/`C` interaction.
5. Tune one variable at a time (moment choice, order, or cooldown), then rerun.

Tune priorities:

- First fix awkwardness.
- Then increase clarity of anticipation/payoff.
- Only then add more variation.
