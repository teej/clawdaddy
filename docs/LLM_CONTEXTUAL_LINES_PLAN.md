# LLM Contextual Lines Plan

## Goal
Increase delightful, context-aware LLM-generated lines while keeping responses short, safe, and non-repetitive.

## Scope
Apply to expressive line stages:
- `ack`
- `status`
- `bridge`

## Phase 1: Context Packet
Add a compact structured context packet to expressive prompts:
- `turn_stage` (`ack|status|bridge`)
- `intent_kind` (`question|command|statement`)
- `time_of_day`
- `session_momentum` (e.g. low/medium/high activity)
- `last_2_captain_messages`
- `last_2_lobster_lines`
- `task_kind` (if known)

Acceptance:
- Generated lines reference user intent/stage more specifically.
- No length/sanitize regressions.

## Phase 2: Style Intensity Control
Introduce runtime delight intensity:
- `low`: plain and efficient
- `mid`: current default
- `high`: more playful and vivid

Wire as setting + prompt variable.

Acceptance:
- Clear tone shift between levels.
- `low` remains concise and stable.

## Phase 3: Stage-Specific Constraints
Tighten constraints per stage:
- `ack`: very short, low-risk, immediate confirmation
- `status`: action-forward, contextual, 3-8 words
- `bridge`: flavorful transition, no factual claims

Acceptance:
- Fewer sanitizer failures per stage.
- Better consistency of role/format.

## Phase 4: Anti-Repetition Memory
Add prompt-time repetition guard:
- Include recent generated lines and banned phrases (sliding window).
- Reject candidate if it overlaps too much with recent phrasing.

Acceptance:
- Noticeably less repeated openers and motifs.
- No increase in fallback frequency.

## Phase 5: Few-Shot Rotation
Create small exemplar banks per stage and rotate examples each turn.

Acceptance:
- Lower determinism in phrasing style.
- Maintains role and brevity constraints.

## Phase 6: Two-Pass Candidate Selection (Status/Bridge First)
For `status` and `bridge`:
1. Generate 2-3 candidates.
2. Select best via rubric:
   - specific to user/context
   - nautical/lobster voice fit
   - non-repetitive
   - within length limits

Fallback to current single-pass on timeout.

Acceptance:
- Higher perceived delight in manual review.
- Timeout/fallback rate does not materially worsen.

## Rollout Order
1. `status` only (highest payoff, lower risk)
2. `bridge`
3. `ack`

## Manual Evaluation Loop (No Instrumentation)
Per phase:
1. Run 10-15 normal interactions.
2. Score each as `A` (delightful), `B` (fine), `C` (flat/awkward).
3. Record one sentence for each `B/C`.
4. Tune one variable only; rerun.

## Risks
- Overly strict prompts can reduce charm.
- More generation steps can increase latency.
- High-intensity mode can become noisy without repetition control.

## Guardrails
- Keep hard max lengths by stage.
- Keep sanitizer + refusal filters unchanged unless explicitly revised.
- Preserve pool fallback paths.

