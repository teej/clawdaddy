# Sprite Animation Research: Low-Frame Characters

How to make a single-sprite lobster feel alive with minimal art assets.

## Current System

DaddyView uses **procedural transform animation** — `IdleStep` sequences that tween scale, rotation, and offset over time — combined with `flashSprite()` for temporary image swaps. This is already the right foundation. The goal is to extend it, not replace it.

Sprite count today: 9 images (base + salute, wink, tilt, thinking, surprised, dizzy, excited, dead).

## Core Technique: Procedural + Sprite Swap Composition

The highest-leverage pattern for low-frame characters is **composing** sprite swaps with procedural transforms. 3 sprite frames combined with squash/stretch/rotation can produce 15-20 distinct visual states. This is what Rain World, Undertale, and Shimeji desktop pets all do.

The existing `playEmote()` functions already nail this — e.g. `.playDead` flashes the dead sprite while running a fall-hold-peek-pop transform sequence.

### What Multiplies Perceived Richness

| Technique | Frames needed | Perceived frames |
|---|---|---|
| Sprite swap alone | 3 | 3 |
| Procedural transforms alone | 1 | ~8 |
| Sprite swap + procedural | 3 | 15-20 |
| Above + secondary motion (follow-through) | 3 | 25+ |

## Tweening Approaches

### Transform Tweening (What We Do)

Interpolate between keyframe values for scale, rotation, offset. The `IdleStep` system does this with `withAnimation(.timingCurve(...))`. Key principles:

- **Never use linear interpolation** for organic motion. Cubic Bezier or spring curves always.
- **Anticipation frame**: A tiny squash (0.08s) before any upward motion. Already in `startListeningMotion()`.
- **Follow-through**: Overshoot the target by ~5% and settle back. Already in `runSequence` via `includeFollowThrough`.
- **1-frame delay for secondary motion**: Offset appendages/accessories by one step behind the primary body. Not currently used but could apply if we ever split the sprite into parts.

### Alpha Crossfade Tweening

Instead of hard-swapping sprites with `flashSprite()`, crossfade between them over ~80ms:

```swift
Image(currentSpriteName)
    .animation(.easeInOut(duration: 0.08), value: currentSpriteName)
```

This softens the visual pop of frame swaps. The Endless Sky engine does this to make 3-frame animations look like 30. Worth trying on the existing `spriteOverride` system — add a `.transition(.opacity)` or animate the image name change.

### Considerations

SwiftUI's `KeyframeAnimator` (macOS 14+) supports independent per-property timing tracks — scale on one curve, rotation on another, position on a third. This is more declarative than the `IdleStep` + `DispatchQueue` approach but less runtime-composable. The current system's strength is that sequences can be built dynamically; `KeyframeAnimator` requires compile-time keyframe definitions.

`PhaseAnimator` (macOS 14+) could clean up the breathing loop — it cycles through discrete phases automatically and handles lifecycle better than the current `didStartBreathing` flag approach.

## Talking Animation

This is the big missing piece. ClawDaddy speaks (via TTS) but the sprite doesn't move its mouth.

### Minimal Viable: 2-Frame Mouth Toggle (Undertale Style)

Undertale uses **2 frames** per character: mouth closed, mouth open. The mouth toggles in sync with the text typewriter. This is the simplest approach that actually works.

**Sprites needed**: `DaddyTalk1` (mouth slightly open) and optionally `DaddyTalk2` (mouth wide open).

**Implementation**: Cycle between base/talk1/talk2 on a timer during the `speaking` state:

```swift
@State private var mouthFrame = 0
@State private var mouthTimer: Timer?

func startTalking() {
    mouthTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
        mouthFrame = (mouthFrame + 1) % 3
    }
}

func stopTalking() {
    mouthTimer?.invalidate()
    mouthFrame = 0
}
```

The frame rate of ~8fps (0.12s per frame) matches the "chunky" feel of pixel art / low-res characters. Faster (0.08s) feels frantic; slower (0.18s) feels sleepy.

### Better: Word-Boundary Sync

`AVSpeechSynthesizerDelegate` provides `willSpeakRangeOfSpeechString` which fires before each word. Toggle between open/closed on each callback for a rhythm that matches actual speech cadence instead of fixed-interval cycling.

```swift
func speechSynthesizer(_ synth: AVSpeechSynthesizer,
                       willSpeakRangeOfSpeechString range: NSRange,
                       utterance: AVSpeechUtterance) {
    DispatchQueue.main.async { self.mouthOpen.toggle() }
}
```

**Caveat**: This delegate has known bugs with character range accuracy on some OS versions. The timer approach is more reliable as a fallback.

### Advanced: Phoneme-Based (Probably Overkill)

macOS 13+ exposes `AVSpeechSynthesisMarker.phoneme` during synthesis. These could map to visemes (visual mouth shapes). The classic Microsoft Agent system used 7 mouth positions:

| Mouth | Sounds |
|---|---|
| Closed | m, b, p, f |
| Slightly open | g, l, "ear" |
| Partially open | n, d, t |
| Open | "hut", "head" |
| Wide open | "hat", "how" |
| Medium width | "ahoy", "hot" |
| Narrow (O-shape) | "hoop", "hope" |

This requires 7 mouth sprites and phoneme-to-viseme mapping. Almost certainly overkill for ClawDaddy's art style, but documented for completeness.

### Enhancing Minimal Mouth Animation

From Siege and the Sandfox devs and general indie game practice:

- **Add a head bob during speech**. Small jerky vertical motion (2-3px, irregular timing) conveys "talking energy" more than mouth alone, especially at small sprite sizes.
- **Break long speech into chunks**. Rather than one endless mouth cycle, pause the mouth briefly between sentences (0.3s closed mouth gap).
- **The body matters more than the mouth at small sizes**. At the scale ClawDaddy renders, a rhythmic body bob + occasional sprite flash may read better than detailed mouth shapes.

## Sprite Recommendations

### Talking Set (Priority)

| Asset name | Description | Used for |
|---|---|---|
| `DaddyTalk1` | Mouth slightly open, body neutral | Speaking frame A |
| `DaddyTalk2` | Mouth wide open, body neutral | Speaking frame B |

These cycle during the `speaking` state. The base `Daddy` sprite (mouth closed) serves as the third frame in the rotation: closed -> slightly open -> wide -> slightly open -> closed.

Just two new sprites turns the speaking state from static to alive.

### Optional Future Sprites

| Asset name | Description | Used for |
|---|---|---|
| `DaddyAngry` | Furrowed brow, clenched claws | Error states, frustration emotes |
| `DaddySmug` | Half-lidded eyes, slight smirk | Milestone celebrations, easter eggs |
| `DaddyLaugh` | Wide open mouth, squinted eyes | Joke reactions, crab rave finish |

## Classic References

| System | Frames per state | Technique |
|---|---|---|
| Tamagotchi | 2 | Alternating hop. Charm from art, not motion |
| Shimeji | 2 per action (25 total) | 2-frame walk cycles "surprisingly work" |
| Undertale | 2 (talk), 2-4 (battle idle) | Mouth toggle synced to typewriter text |
| BonziBuddy | ~14 per animation (148 animations) | 7 mouth overlays composited on last frame |
| Mega Man | 3 per run cycle | Strong keyframes > smooth in-betweens |

Key insight from pixel art animators: **snappy 3-frame cycles feel more alive than smooth 8-frame ones**. Reducing frames forces stronger pose contrast between keyframes, which reads as more energetic.

## Integration Path for DaddyView

1. **Talking** (biggest bang for buck): Add `DaddyTalk1`/`DaddyTalk2` sprites. Add mouth cycling timer in DaddyView triggered by `speaking` state. Combine with subtle head bob (reuse `IdleStep` sequence).

2. **Crossfade softening**: Add `.animation(.easeInOut(duration: 0.08), value: spriteImageName)` to the main Image view so sprite swaps crossfade instead of hard-cutting.

3. **Speech-synced mouth**: Wire `AVSpeechSynthesizerDelegate.willSpeakRangeOfSpeechString` through to DaddyView to toggle mouth on word boundaries instead of fixed timer.

## Sources

- [Endless Sky Animation Tweening](https://github.com/endless-sky/endless-sky/wiki/AnimationTweening)
- [SLYNYRD Pixel Art Animation](https://www.slynyrd.com/blog/2018/8/19/pixelblog-8-intro-to-animation)
- [Sandro Maglione Pixel Art Guide](https://www.sandromaglione.com/articles/pixel-art-character-animations-guide)
- [ANIMIND 2D Mouth Positions](https://www.animindstudio.com/blog/animating2dmouthpositions)
- [Siege and the Sandfox Talking Sprites](https://www.indiedb.com/tutorials/talking-sprite-animations)
- [Microsoft Agent Animations](https://learn.microsoft.com/en-us/windows/win32/lwef/animations)
- [Kilkakon Shimeji Desktop Pet](https://kilkakon.com/shimeji/)
- [The Spriters Resource Undertale](https://www.spriters-resource.com/pc_computer/undertale/)
- [Apple AVSpeechSynthesizerDelegate](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate/1619681-speechsynthesizer)
- [Apple PhaseAnimator](https://developer.apple.com/documentation/swiftui/phaseanimator)
- [AppCoda KeyframeAnimator](https://www.appcoda.com/keyframeanimator/)
- [SwiftUI Lab TimelineView](https://swiftui-lab.com/swiftui-animations-part4/)
