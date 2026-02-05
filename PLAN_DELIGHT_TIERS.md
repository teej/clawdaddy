# ClawDaddy Delight Roadmap (All Tiers)

## What's Already Done (Tier 0)
- Single-sprite animation system: breathing, idle variants (drift, soft bob, anchor drop, proud swing, head tilt)
- Acknowledgement bounce (standard + big based on transcript length)
- Sub-agent reactions: perk (working), alert (waiting/error), settle (done)
- Salute + dance on OpenClaw connect greeting
- Emotes: wink, tilt, surprised, backflip, walk-the-plank
- Follow-through on large motions, custom easing curve throughout
- Typewriter text reveal on ClawDaddy speech bubbles
- Bubble entrance/exit animations (slide-in, fade-out)
- Lobster entrance/exit animations (scale+fade with spring)
- Time-of-day greetings (4 time brackets + generic pool)
- 6 sprite variants: Daddy, DaddySalute, DaddyThinking, DaddyTilt, DaddyWink, DaddySurprised
- Thinking hold (2s minimum before state transition)

## Design Principles
1. **Less is more.** The lobster is a presence, not a conversation partner. Err on too quiet.
2. **Frequency is everything.** Delightful vs annoying is purely frequency. When in doubt, make it rarer.
3. **Layer channels, don't amplify one.** Glow + bounce > bigger bounce. Sound + motion > more motion.
4. **React to what already happens.** Best features attach to events in the user's existing workflow.
5. **Personality in the margins.** Errors, delays, and absences are where character matters most.
6. **Never punish absence.** Celebrate presence, don't guilt-trip on missed days.

---

## Tier 1 -- Instant Feel (quick wins, < 20 lines each)

### 1A. Anticipation Squash on Push-to-Talk
When the user presses Left Control, immediately play a 0.08s downward squash (scaleX: 1.06, scaleY: 0.94) before the listening animation kicks in. Makes push-to-talk feel like pressing a physical button.

**File:** `DaddyView.swift` -- add a brief squash step in `startListeningMotion()` or via a new `listenAnticipation` flag.

### 1B. Glow Pulse on Acknowledge
When `playAcknowledge()` fires, briefly flash glow to warm red/orange (Color.red.opacity(0.4), radius 12) for 0.15s, then fade to zero. Multi-channel feedback (motion + light) instead of motion only.

**File:** `DaddyView.swift` -- add `@State private var ackGlowActive = false`, use in `glowColor`/`glowRadius`, clear with `asyncAfter`.

### 1C. Pirate Error Messages
Replace raw exception strings with themed error copy:
- Connection errors: "Lost the signal, cap'n. The sea's rough today."
- Timeouts: "Waited too long at port. Let me try another route."
- Generic: "Hit a reef there. Give me a moment to patch the hull."

Trigger `DaddySurprised` sprite + alert reaction on ClawDaddy's own error bubbles.

**Files:** `backend/main.py` (error message formatting), `ContentView.swift` (reaction trigger on error).

---

## Tier 2 -- Personality & Awareness

### 2A. Return-from-Absence Reaction
Track `last_interaction_at` in StateManager. If 30+ minutes since last voice input, the next push-to-talk triggers an excited reaction (DaddySurprised flash + big bounce) and a welcome-back ACK pool: "There ye are, cap'n!", "Thought ye'd walked the plank!", "The crew was getting restless!"

**Files:** `backend/state.py` (timestamp tracking), `backend/openclaw_client.py` (reunion ACK pool), `ContentView.swift` (reunion reaction trigger).

### 2B. Micro-Nap / Sleep State
After 5+ minutes idle with no interaction:
- Slow breathing to 12s cycle (from 6s)
- Reduce idle variant frequency to 30-60s intervals (from 12-20s)
- Optionally add `DaddySleepy` sprite (half-closed eyes)
- On push-to-talk: startled reaction, vertical stretch, then normal listening

**File:** `DaddyView.swift` -- add idle duration tracking, adjust animation params, add wake-up sequence.

### 2C. Time-of-Day Visual Atmosphere
Extend existing time-of-day greetings to the visual layer:
- Morning (6-12): slightly faster breathing (5s), more frequent idle variants
- Afternoon (12-17): current defaults
- Evening (17-21): warmer glow tint on listening (shift green toward amber)
- Night (21-6): slower breathing (8s), reduced idle frequency, dimmed glow

**File:** `DaddyView.swift` -- add `timeOfDay` enum, scale existing animation constants.

### 2D. Contextual ACK Line Variants
Extend backend ACK pools based on command context:
- Short commands (< 10 words): quick ACKs ("On it.", "Aye.")
- Long commands (> 30 words): "That's a tall order, cap'n."
- Repeated intent within 5 min: "Again? Aye aye."
- First command of the day: "First order of the day -- let's make it count."

**File:** `backend/openclaw_client.py` -- add `_pick_ack_line(text, context)` with sub-pools.

### 2E. Dark Mode Reaction
Detect macOS appearance changes via `NSApp.effectiveAppearance`. On transition:
- Dark mode: settle reaction, adjust bubble background to dark variant
- Light mode: perk reaction

**Files:** `ContentView.swift` (appearance observer), `SpeechBubbleView.swift` (dark variant styling).

---

## Tier 3 -- Discovery & Shareability

### 3A. Hidden Emote Discovery
Add 3 undocumented emotes. Do NOT document them. Let users discover via experimentation:
- **"play dead"**: 90-degree rotation fall, hold 2s, hop back up
- **"spin"**: 720-degree horizontal spin (doubled backflip, less vertical)
- **"crab rave"**: rapid side-to-side shimmy with wobble

**Files:** `DaddyView.swift` (new EmoteStyle cases + animations), `ContentView.swift` (voice command wiring).

### 3B. Window Drag Reaction
Detect window movement via `NSWindow.didMoveNotification`:
- Short move (> 50pt): surprised sprite flash + alert reaction
- After settling: settle reaction

**File:** `ContentView.swift` or `WindowConfigurator` -- add notification observer.

### 3C. Thinking Status Flavor Text
During long-running OpenClaw processing (> 5s), emit pirate-themed status updates as speech bubbles: "Consulting the charts...", "Checking the rigging...", "Gathering the crew..."

**File:** `backend/openclaw_client.py` -- emit periodic status updates during long waits.

### 3D. Notification Dot
When a sub-agent completes and user hasn't interacted in 60+ seconds, show a small pulsing 6pt circle above the lobster. Disappears on next push-to-talk.

**File:** `ContentView.swift` -- add `hasUnread` flag, small Circle overlay in `bottomRow`.

---

## Tier 4 -- Ambient Polish & Progression

### 4A. Sound Cues (3 sounds, off by default)
Exactly 3 optional sounds, togglable via right-click menu:
1. **Claw snap** (0.1s) -- push-to-talk activates
2. **Bubble pop** (0.15s) -- speech bubble appears
3. **Settle chirp** (0.2s) -- sub-agent completes

Volume 0.3-0.4. Off by default.

**Files:** New `SoundManager.swift`, audio assets, right-click menu in `ContentView.swift`.

### 4B. Bubble Particles During Thinking
Small translucent circles (3-5pt) float upward from the lobster during thinking state. 2-3 at a time, slight horizontal drift, fade out. Reinforces "processing" beyond the bob.

**File:** New `BubbleParticleView.swift`, overlay in `ContentView.swift`.

### 4C. Streak Awareness
Track consecutive days opened (UserDefaults). At milestones, special greeting:
- Day 3: "Three days at sea, cap'n. Getting our sea legs."
- Day 7: "A full week on the water! Ye be a true sailor."
- Day 30: salute + dance + "A month! The crew salutes ye, cap'n."

Never punish broken streaks. Return-from-absence (2A) covers gaps warmly.

**Files:** `ContentView.swift` (UserDefaults tracking), `backend/openclaw_client.py` (milestone ACK pool).

### 4D. Interaction Milestones
Track total voice commands (persisted UserDefaults). One-time celebrations at 10, 50, 100, 500, 1000:
- 10: salute + "Tenth order! The crew remembers every one."
- 100: backflip + dance + "A hundred orders! Ye run a tight ship."
- 1000: walk-the-plank + peek + "A THOUSAND. Captain legend."

Fire once ever per milestone.

**Files:** `ContentView.swift` (counter + milestone checks), `backend/openclaw_client.py` (milestone messages).

### 4E. Rare Unprompted Observations
At most once per 2-hour session, surface a single flavor observation:
- "Calm seas today." (long idle)
- "The crew's been busy." (3+ sub-agents completed)
- "Good haul, cap'n." (productive session)

Never while user is speaking/thinking. Track session stats in backend.

**File:** `backend/openclaw_client.py` (session stats + observation trigger).

### 4F. Session Summary
On app quit or end-of-day: "Today's log: 12 orders given, 8 missions complete, 2 hit the rocks. Productive day on deck, cap'n." Appears as final speech bubble.

**Files:** `backend/state.py` (session counters), `backend/main.py` (quit hook).

---

## Tier 5 -- Advanced Presence (experimental)

### 5A. Cursor Proximity Awareness
Detect cursor near lobster window via `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)`. Within ~100pt: subtle perk + head tilt sprite 0.5s. 10-second cooldown between triggers.

### 5B. Active App Awareness
Use `NSWorkspace.shared.frontmostApplication` for atmosphere tuning only (not suggestions). Rapid app switching = slightly more frequent idle variants. Deep focus in one app = calmer idle. Ultra-rare flavor text: "Heavy seas in Terminal today."

### 5C. Battery Awareness (laptops only)
Read battery via IOPowerSources. Below 20%: concerned head tilt + "Running low on juice, cap'n." Once per threshold crossing.

### 5D. Window Edge Awareness
Read `window.frame` vs screen edges. Near bottom: "resting" (flatten squash, reduced motion). Corner: settling-in animation.

### 5E. Screenshot Pose Mode
Right-click menu "Strike a Pose": random emote with peak pose held for 3 seconds instead of normal 0.35s. Long enough to screenshot.

### 5F. Spontaneous Mischief (opt-in)
Ultra-rare (once per 30-60 min idle): spontaneous walk-the-plank or new "claw snap" idle. Purely visual, never disruptive. Add 0.03 ultra-rare tier to `playIdleVariant()` roll.
