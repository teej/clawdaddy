import SwiftUI

// MARK: - Enums & Types

enum DaddyAnimState: Equatable {
    case idle, listening, thinking, speaking, sleeping, waitingForInput
}

enum DaddyEvent {
    case stateChanged(DaddyAnimState)
    case acknowledge(AckStyle)
    case reaction(ReactionStyle)
    case salute
    case emote(EmoteStyle)
    case randomEmote
    case dance
    case talkingChanged(Bool)
}

enum AckStyle: Int {
    case standard
    case big
}

enum ReactionStyle: Int {
    case none
    case perk
    case settle
    case alert
}

enum EmoteStyle: Int, CaseIterable {
    case none
    case wink
    case tilt
    case surprised
    case backflip
    case plank
    case playDead
    case spin
    case crabRave
    case nod
    case shake
    case bow
}

struct AnimationStep {
    let rotation: Double
    let offset: CGSize
    let scaleX: CGFloat
    let scaleY: CGFloat
    let duration: Double
    let sprite: String?

    init(rotation: Double, offset: CGSize, scaleX: CGFloat, scaleY: CGFloat, duration: Double, sprite: String? = nil) {
        self.rotation = rotation
        self.offset = offset
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.duration = duration
        self.sprite = sprite
    }
}

// MARK: - DaddyAnimationModel

@Observable
final class DaddyAnimationModel {
    // Public state (read by DaddyView)
    private(set) var animState: DaddyAnimState = .idle
    private(set) var spriteOverride: String? = nil
    private(set) var idleRotation: Double = 0
    private(set) var idleOffset: CGSize = .zero
    private(set) var idleScaleX: CGFloat = 1.0
    private(set) var idleScaleY: CGFloat = 1.0
    private(set) var breathPhase = false
    private(set) var listeningPhase = false
    private(set) var thinkingPhase = false
    private(set) var waitingPhase = false
    private(set) var talkMouthOpen = false
    private(set) var isPlayingVariant = false
    private(set) var isSaluting = false

    private var tasks: [String: Task<Void, Never>] = [:]
    private var didStart = false
    private var typewriterTalking = false
    private var spriteGeneration = 0

    // MARK: - Keyed Task Management

    private func setTask(_ key: String, _ block: @escaping @MainActor () async -> Void) {
        tasks[key]?.cancel()
        tasks[key] = Task { @MainActor in await block() }
    }

    private func cancelTask(_ key: String) {
        tasks[key]?.cancel()
        tasks.removeValue(forKey: key)
    }

    // MARK: - Lifecycle

    func start() {
        guard !didStart else { return }
        didStart = true
        startBreathing()
        startIdleLoop()
        if animState == .thinking {
            startThinkingMotion()
            startThinkingLoop()
        }
    }

    func stop() {
        for (_, task) in tasks {
            task.cancel()
        }
        tasks.removeAll()
    }

    // MARK: - Event Dispatcher

    func send(_ event: DaddyEvent) {
        switch event {
        case .stateChanged(let newState):
            handleStateChange(newState)
        case .acknowledge(let style):
            playAcknowledge(style: style)
        case .reaction(let style):
            playReaction(style: style)
        case .salute:
            playSalute()
        case .emote(let style):
            playEmote(style: style)
        case .randomEmote:
            if let style = EmoteStyle.allCases.filter({ $0 != .none }).randomElement() {
                playEmote(style: style)
            }
        case .dance:
            playDance()
        case .talkingChanged(let talking):
            typewriterTalking = talking
            if talking {
                // Stop thinking visuals so mouth sprite can take over
                cancelTask("thinking")
                cancelTask("thinkingMotion")
                cancelTask("sprite")
                thinkingPhase = false
                spriteGeneration += 1
                spriteOverride = nil
                startTalkCycling()
            } else {
                stopTalkCycling()
                // Resume thinking animation if still in thinking state
                if animState == .thinking {
                    startThinkingMotion()
                    startThinkingLoop()
                }
            }
        }
    }

    // MARK: - State Change Handler

    private func handleStateChange(_ newState: DaddyAnimState) {
        let wasSleeping = animState == .sleeping
        animState = newState

        if newState != .idle && newState != .sleeping {
            resetIdleVariant()
            isPlayingVariant = false
            // Cancel sequence when entering active state so orphaned steps don't run.
            // Allow sequences to finish when returning to idle/sleeping (e.g. salute after recording).
            cancelTask("sequence")
            cancelTask("sprite")
        }

        if newState == .listening {
            if wasSleeping {
                playWakeUp()
            }
            startListeningMotion()
        } else {
            listeningPhase = false
        }

        if newState == .thinking {
            if !typewriterTalking {
                startThinkingMotion()
                startThinkingLoop()
            }
        } else {
            thinkingPhase = false
            cancelTask("thinking")
            cancelTask("thinkingMotion")
            // Clear stale thinking sprite flash
            cancelTask("sprite")
            if spriteOverride == "DaddyThinking" {
                spriteGeneration += 1
                spriteOverride = nil
            }
        }

        if newState != .speaking && !typewriterTalking {
            stopTalkCycling()
        }

        if newState == .waitingForInput {
            startWaitingMotion()
        } else {
            waitingPhase = false
            cancelTask("waiting")
        }
    }

    // MARK: - Computed Properties (read by view)

    var currentImageName: String {
        if isSaluting {
            return "DaddySalute"
        }
        if let spriteOverride {
            return spriteOverride
        }
        if talkMouthOpen && (animState == .speaking || typewriterTalking) {
            return "DaddyTalk"
        }
        return "Daddy"
    }

    var breathScale: CGFloat {
        let amplitude: CGFloat = animState == .sleeping ? 0.004 : 0.008
        return breathPhase ? (1.0 + amplitude) : (1.0 - amplitude)
    }

    var breathRotation: Double {
        guard animState == .idle || animState == .sleeping else { return 0 }
        let amplitude = animState == .sleeping ? 0.15 : 0.25
        return breathPhase ? amplitude : -amplitude
    }

    var listeningScale: CGFloat {
        animState == .listening ? 1.03 : 1.0
    }

    var thinkingScale: CGFloat {
        guard animState == .thinking, !isPlayingVariant else { return 1.0 }
        return thinkingPhase ? 1.01 : 0.99
    }

    var speakingScaleX: CGFloat {
        guard animState == .speaking else { return 1.0 }
        return talkMouthOpen ? 1.01 : 0.995
    }

    var speakingScaleY: CGFloat {
        guard animState == .speaking else { return 1.0 }
        return talkMouthOpen ? 0.985 : 1.005
    }

    var speakingOffset: CGSize {
        guard animState == .speaking else { return .zero }
        return talkMouthOpen ? CGSize(width: 0, height: 1.5) : CGSize(width: 0, height: -0.5)
    }

    var speakingRotation: Double {
        guard animState == .speaking else { return 0 }
        return talkMouthOpen ? 0.4 : -0.4
    }

    var listeningRotation: Double {
        guard animState == .listening else { return 0 }
        return listeningPhase ? 1.2 : -1.2
    }

    var thinkingRotation: Double {
        guard animState == .thinking, !isPlayingVariant else { return 0 }
        return thinkingPhase ? 1.5 : -1.5
    }

    var listeningOffset: CGSize {
        guard animState == .listening else { return .zero }
        return listeningPhase ? CGSize(width: 0, height: 1) : CGSize(width: 0, height: -1)
    }

    var thinkingOffset: CGSize {
        guard animState == .thinking, !isPlayingVariant else { return .zero }
        return thinkingPhase ? CGSize(width: 1, height: 3) : CGSize(width: -1, height: -3)
    }

    var waitingRotation: Double {
        guard animState == .waitingForInput, !isPlayingVariant else { return 0 }
        return waitingPhase ? 2.0 : -2.0
    }

    var waitingOffset: CGSize {
        guard animState == .waitingForInput, !isPlayingVariant else { return .zero }
        return waitingPhase ? CGSize(width: 2, height: 0) : CGSize(width: -2, height: 0)
    }

    var finalScaleX: CGFloat {
        breathScale * idleScaleX * listeningScale * thinkingScale * speakingScaleX
    }

    var finalScaleY: CGFloat {
        breathScale * idleScaleY * listeningScale * thinkingScale * speakingScaleY
    }

    var finalRotation: Angle {
        Angle(degrees: idleRotation + listeningRotation + thinkingRotation + breathRotation + speakingRotation + waitingRotation)
    }

    var finalOffset: CGSize {
        let listenOffset = CGSize(width: 0, height: animState == .listening ? -2 : 0)
        return CGSize(
            width: idleOffset.width + listenOffset.width + listeningOffset.width + thinkingOffset.width + speakingOffset.width + waitingOffset.width,
            height: idleOffset.height + listenOffset.height + listeningOffset.height + thinkingOffset.height + speakingOffset.height + waitingOffset.height
        )
    }

    var glowColor: Color {
        if animState == .listening {
            return Color.green.opacity(0.85)
        }
        if animState == .waitingForInput {
            return Color.orange.opacity(0.5)
        }
        return Color.clear
    }

    var glowRadius: CGFloat {
        if animState == .listening || animState == .waitingForInput {
            return 3
        }
        return 0
    }

    // MARK: - Breathing

    private func startBreathing() {
        breathPhase = false
        withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
            breathPhase = true
        }
    }

    // MARK: - Idle Loop

    private func startIdleLoop() {
        setTask("idle") {
            while !Task.isCancelled {
                let sleeping = self.animState == .sleeping
                let delay = sleeping
                    ? Double.random(in: 30.0...60.0)
                    : Double.random(in: 12.0...20.0)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { break }
                if self.animState == .sleeping {
                    self.playSleepyBob()
                } else if self.animState == .idle {
                    self.playIdleVariant()
                }
            }
        }
    }

    // MARK: - Listening Motion

    private func startListeningMotion() {
        withAnimation(.easeOut(duration: 0.08)) {
            idleScaleX = 1.06
            idleScaleY = 0.94
        }
        setTask("listeningSquash") {
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.easeOut(duration: 0.08)) {
                self.idleScaleX = 1.0
                self.idleScaleY = 1.0
            }
        }
        listeningPhase = false
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            listeningPhase = true
        }
    }

    // MARK: - Thinking Motion & Loop

    private func startThinkingMotion() {
        thinkingPhase = false
        setTask("thinkingMotion") {
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 1.2)) {
                    self.thinkingPhase.toggle()
                }
                try? await Task.sleep(nanoseconds: 1_150_000_000)
            }
        }
    }

    private func startThinkingLoop() {
        setTask("thinking") {
            while !Task.isCancelled {
                let delay = Double.random(in: 2.0...3.6)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { break }
                guard self.animState == .thinking, !self.isPlayingVariant else { continue }
                let hold = Double.random(in: 0.9...1.3)
                self.flashSprite("DaddyThinking", duration: hold)
            }
        }
    }

    // MARK: - Talk Cycling

    private func startTalkCycling() {
        talkMouthOpen = false
        setTask("talk") {
            while !Task.isCancelled {
                self.talkMouthOpen.toggle()
                let interval = UInt64.random(in: 120_000_000...180_000_000)
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func stopTalkCycling() {
        cancelTask("talk")
        talkMouthOpen = false
    }

    // MARK: - Waiting Motion

    private func startWaitingMotion() {
        waitingPhase = false
        setTask("waiting") {
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.8)) {
                    self.waitingPhase.toggle()
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    // MARK: - Sequence Runner (cancellable async)

    private func runSequence(_ steps: [AnimationStep], requireIdle: Bool, followThrough: Bool = false) {
        setTask("sequence") {
            var allSteps = steps
            if followThrough { allSteps += self.followThroughSteps }
            for step in allSteps {
                if Task.isCancelled { break }
                if requireIdle && self.animState != .idle && self.animState != .sleeping { break }
                guard self.isPlayingVariant else { break }
                if let sprite = step.sprite {
                    self.spriteOverride = sprite
                }
                withAnimation(self.stepAnimation(step.duration)) {
                    self.idleRotation = step.rotation
                    self.idleOffset = step.offset
                    self.idleScaleX = step.scaleX
                    self.idleScaleY = step.scaleY
                }
                try? await Task.sleep(nanoseconds: UInt64(step.duration * 1_000_000_000))
            }
            self.resetIdleVariant()
            self.isPlayingVariant = false
            self.spriteOverride = nil
        }
    }

    private func stepAnimation(_ duration: Double) -> Animation {
        Animation.timingCurve(0.22, 0.61, 0.36, 1.0, duration: duration)
    }

    private var followThroughSteps: [AnimationStep] {
        [
            AnimationStep(rotation: 1.4, offset: CGSize(width: 1, height: -1), scaleX: 1.01, scaleY: 0.99, duration: 0.12),
            AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.16),
        ]
    }

    // MARK: - Sprite Flash (cancellable)

    private func flashSprite(_ name: String, duration: Double) {
        spriteGeneration += 1
        let gen = spriteGeneration
        spriteOverride = name
        setTask("sprite") {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            // Clear only if no newer sprite was set (avoids clearing a different flash)
            if self.spriteGeneration == gen {
                self.spriteOverride = nil
            }
        }
    }

    // MARK: - Reset

    private func resetIdleVariant() {
        idleRotation = 0
        idleOffset = .zero
        idleScaleX = 1.0
        idleScaleY = 1.0
    }

    // MARK: - Idle Variants

    private func playIdleVariant() {
        if isPlayingVariant { return }
        let roll = Double.random(in: 0...1)
        if roll < 0.03 {
            playEmote(style: .plank)
        } else if roll < 0.15 {
            playRareIdle()
        } else if roll < 0.55 {
            playCommonIdle()
        }
    }

    private func playCommonIdle() {
        isPlayingVariant = true
        let choice = Int.random(in: 0...2)
        switch choice {
        case 0: playDrift()
        case 1: playSoftBob()
        default: playStretch()
        }
    }

    private func playRareIdle() {
        isPlayingVariant = true
        let choice = Int.random(in: 0...4)
        switch choice {
        case 0: playAnchorDrop()
        case 1: playProudSwing()
        case 2: playHeadTilt()
        case 3: playPeek()
        default: playShimmy()
        }
    }

    private func playDrift() {
        runSequence([
            AnimationStep(rotation: -1.6, offset: CGSize(width: -2, height: 1), scaleX: 1.01, scaleY: 0.99, duration: 0.4),
            AnimationStep(rotation: 1.8, offset: CGSize(width: 2, height: 0), scaleX: 1.01, scaleY: 0.99, duration: 0.45),
            AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.35),
        ], requireIdle: true)
    }

    private func playSoftBob() {
        runSequence([
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 2), scaleX: 1.02, scaleY: 0.98, duration: 0.3),
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -3), scaleX: 0.99, scaleY: 1.03, duration: 0.36),
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 1), scaleX: 1.01, scaleY: 0.99, duration: 0.24),
            AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.28),
        ], requireIdle: true)
    }

    private func playAnchorDrop() {
        runSequence([
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 6), scaleX: 1.08, scaleY: 0.9, duration: 0.16),
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -8), scaleX: 0.96, scaleY: 1.08, duration: 0.2),
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 3), scaleX: 1.04, scaleY: 0.96, duration: 0.18),
            AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.24),
        ], requireIdle: true, followThrough: true)
    }

    private func playProudSwing() {
        runSequence([
            AnimationStep(rotation: -7.0, offset: CGSize(width: -4, height: 0), scaleX: 1.04, scaleY: 0.98, duration: 0.18),
            AnimationStep(rotation: 7.0, offset: CGSize(width: 4, height: 0), scaleX: 1.04, scaleY: 0.98, duration: 0.18),
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -4), scaleX: 1.06, scaleY: 0.97, duration: 0.2),
            AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.26),
        ], requireIdle: true, followThrough: true)
    }

    private func playHeadTilt() {
        runSequence([
            AnimationStep(rotation: -6.0, offset: CGSize(width: -2, height: 1), scaleX: 1.02, scaleY: 0.98, duration: 0.2, sprite: "DaddyTilt"),
            AnimationStep(rotation: 4.0, offset: CGSize(width: 2, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.2),
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -2), scaleX: 1.01, scaleY: 0.99, duration: 0.22),
        ], requireIdle: true, followThrough: true)
    }

    private func playStretch() {
        runSequence([
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -5), scaleX: 0.96, scaleY: 1.06, duration: 0.3),
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -3), scaleX: 0.97, scaleY: 1.04, duration: 0.4),
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 3), scaleX: 1.04, scaleY: 0.97, duration: 0.2),
            AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.25),
        ], requireIdle: true, followThrough: true)
    }

    private func playPeek() {
        runSequence([
            AnimationStep(rotation: -4.0, offset: CGSize(width: -6, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.2),
            AnimationStep(rotation: -6.0, offset: CGSize(width: -10, height: -2), scaleX: 1.0, scaleY: 1.0, duration: 0.3),
            AnimationStep(rotation: -4.0, offset: CGSize(width: -6, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.15),
            AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.2),
        ], requireIdle: true, followThrough: true)
    }

    private func playShimmy() {
        runSequence([
            AnimationStep(rotation: -3.0, offset: CGSize(width: -2, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.1),
            AnimationStep(rotation: 3.0, offset: CGSize(width: 2, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.1),
            AnimationStep(rotation: -2.0, offset: CGSize(width: -1, height: 0), scaleX: 1.01, scaleY: 0.99, duration: 0.1),
            AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.15),
        ], requireIdle: true)
    }

    private func playSleepyBob() {
        if isPlayingVariant { return }
        isPlayingVariant = true
        runSequence([
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 1), scaleX: 1.01, scaleY: 0.99, duration: 0.5),
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -1), scaleX: 0.99, scaleY: 1.01, duration: 0.6),
            AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.4),
        ], requireIdle: true)
    }

    private func playWakeUp() {
        resetIdleVariant()
        isPlayingVariant = true
        runSequence([
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -8), scaleX: 0.96, scaleY: 1.08, duration: 0.12, sprite: "DaddySurprised"),
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -4), scaleX: 0.95, scaleY: 1.1, duration: 0.2),
            AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.16),
        ], requireIdle: false, followThrough: true)
    }

    // MARK: - Acknowledge

    private func playAcknowledge(style: AckStyle) {
        resetIdleVariant()
        isPlayingVariant = true
        isSaluting = true

        let bounceSteps: [AnimationStep]
        switch style {
        case .big:
            bounceSteps = [
                AnimationStep(rotation: -2.0, offset: CGSize(width: 0, height: 8), scaleX: 1.14, scaleY: 0.88, duration: 0.08),
                AnimationStep(rotation: 2.0, offset: CGSize(width: 0, height: -20), scaleX: 0.94, scaleY: 1.16, duration: 0.18),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 7), scaleX: 1.08, scaleY: 0.92, duration: 0.12),
                AnimationStep(rotation: -1.0, offset: CGSize(width: 0, height: -12), scaleX: 0.97, scaleY: 1.08, duration: 0.16),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 3), scaleX: 1.03, scaleY: 0.97, duration: 0.12),
                AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.2),
            ]
        case .standard:
            bounceSteps = [
                AnimationStep(rotation: -1.0, offset: CGSize(width: 0, height: 6), scaleX: 1.1, scaleY: 0.9, duration: 0.08),
                AnimationStep(rotation: 1.0, offset: CGSize(width: 0, height: -16), scaleX: 0.95, scaleY: 1.12, duration: 0.18),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 5), scaleX: 1.06, scaleY: 0.94, duration: 0.12),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -9), scaleX: 0.98, scaleY: 1.06, duration: 0.16),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 2), scaleX: 1.02, scaleY: 0.98, duration: 0.12),
                AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.2),
            ]
        }
        runSequence(bounceSteps, requireIdle: false, followThrough: true)

        // Hold salute sprite on its own task key (survives state changes)
        let total = bounceSteps.reduce(0.0) { $0 + $1.duration }
        let holdDuration = max(0.8, total)
        setTask("salute") {
            try? await Task.sleep(nanoseconds: UInt64(holdDuration * 1_000_000_000))
            if !Task.isCancelled {
                self.isSaluting = false
            }
        }
    }

    // MARK: - Dance

    private func playDance() {
        resetIdleVariant()
        isPlayingVariant = true
        runSequence([
            AnimationStep(rotation: -8.0, offset: CGSize(width: -4, height: 0), scaleX: 1.04, scaleY: 0.98, duration: 0.12, sprite: "DaddyExcited"),
            AnimationStep(rotation: 8.0, offset: CGSize(width: 4, height: 0), scaleX: 1.04, scaleY: 0.98, duration: 0.12),
            AnimationStep(rotation: -12.0, offset: CGSize(width: -6, height: -2), scaleX: 1.08, scaleY: 0.94, duration: 0.14),
            AnimationStep(rotation: 12.0, offset: CGSize(width: 6, height: -2), scaleX: 1.08, scaleY: 0.94, duration: 0.14),
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 5), scaleX: 1.12, scaleY: 0.9, duration: 0.12),
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -12), scaleX: 0.95, scaleY: 1.12, duration: 0.18),
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 4), scaleX: 1.06, scaleY: 0.96, duration: 0.12),
            AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.2),
        ], requireIdle: false, followThrough: true)
    }

    // MARK: - Reaction

    private func playReaction(style: ReactionStyle) {
        guard style != .none else { return }
        guard !isPlayingVariant else { return }
        resetIdleVariant()
        isPlayingVariant = true
        let steps: [AnimationStep]
        switch style {
        case .perk:
            steps = [
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 3), scaleX: 1.04, scaleY: 0.96, duration: 0.1),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -6), scaleX: 0.98, scaleY: 1.05, duration: 0.16),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 2), scaleX: 1.02, scaleY: 0.98, duration: 0.12),
            ]
        case .settle:
            steps = [
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 4), scaleX: 1.05, scaleY: 0.95, duration: 0.14),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -2), scaleX: 0.99, scaleY: 1.02, duration: 0.14),
            ]
        case .alert:
            steps = [
                AnimationStep(rotation: -4.0, offset: CGSize(width: -2, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.1, sprite: "DaddySurprised"),
                AnimationStep(rotation: 4.0, offset: CGSize(width: 2, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.1),
                AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.12),
            ]
        case .none:
            steps = []
        }
        runSequence(steps, requireIdle: false, followThrough: true)
    }

    // MARK: - Salute

    private func playSalute() {
        resetIdleVariant()
        isPlayingVariant = true
        isSaluting = true

        let saluteHold: Double = 1.4
        let steps: [AnimationStep] = [
            AnimationStep(rotation: -2.0, offset: CGSize(width: 0, height: 5), scaleX: 1.04, scaleY: 0.96, duration: 0.12, sprite: "DaddySalute"),
            AnimationStep(rotation: 2.0, offset: CGSize(width: 0, height: -6), scaleX: 0.98, scaleY: 1.05, duration: 0.18),
            AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 2), scaleX: 1.02, scaleY: 0.98, duration: 0.16),
            AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.2),
        ]
        runSequence(steps, requireIdle: false, followThrough: true)

        let total = steps.reduce(0.0) { $0 + $1.duration }
        let releaseDelay = max(saluteHold, total + 0.2)
        setTask("salute") {
            try? await Task.sleep(nanoseconds: UInt64(releaseDelay * 1_000_000_000))
            if !Task.isCancelled {
                self.isSaluting = false
            }
        }
    }

    // MARK: - Emotes

    private func playEmote(style: EmoteStyle) {
        guard style != .none else { return }
        guard !isPlayingVariant else { return }
        resetIdleVariant()
        isPlayingVariant = true
        var useFollowThrough = true
        let steps: [AnimationStep]
        switch style {
        case .wink:
            steps = [
                AnimationStep(rotation: -2.0, offset: CGSize(width: 0, height: 4), scaleX: 1.04, scaleY: 0.96, duration: 0.12, sprite: "DaddyWink"),
                AnimationStep(rotation: 1.0, offset: CGSize(width: 0, height: -5), scaleX: 0.99, scaleY: 1.03, duration: 0.16),
            ]
        case .tilt:
            steps = [
                AnimationStep(rotation: -5.0, offset: CGSize(width: -2, height: 2), scaleX: 1.02, scaleY: 0.98, duration: 0.2, sprite: "DaddyTilt"),
                AnimationStep(rotation: 3.0, offset: CGSize(width: 2, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.2),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -1), scaleX: 1.01, scaleY: 0.99, duration: 0.2),
            ]
        case .surprised:
            steps = [
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 6), scaleX: 1.06, scaleY: 0.94, duration: 0.12, sprite: "DaddySurprised"),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -8), scaleX: 0.98, scaleY: 1.08, duration: 0.18),
            ]
        case .backflip:
            useFollowThrough = false
            steps = [
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 6), scaleX: 1.12, scaleY: 0.88, duration: 0.12),
                AnimationStep(rotation: 180.0, offset: CGSize(width: 0, height: -30), scaleX: 0.95, scaleY: 1.05, duration: 0.28),
                AnimationStep(rotation: 360.0, offset: CGSize(width: 0, height: -8), scaleX: 1.0, scaleY: 1.0, duration: 0.24),
                AnimationStep(rotation: 360.0, offset: CGSize(width: 0, height: 5), scaleX: 1.1, scaleY: 0.9, duration: 0.1),
                AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.18),
            ]
        case .plank:
            useFollowThrough = false
            steps = [
                AnimationStep(rotation: 4.0, offset: CGSize(width: 10, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.2),
                AnimationStep(rotation: 6.0, offset: CGSize(width: 200, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.3),
                AnimationStep(rotation: 6.0, offset: CGSize(width: 200, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.6),
                AnimationStep(rotation: -4.0, offset: CGSize(width: 120, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.25, sprite: "DaddySurprised"),
                AnimationStep(rotation: -4.0, offset: CGSize(width: 120, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.3),
                AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.3),
            ]
        case .playDead:
            useFollowThrough = false
            steps = [
                AnimationStep(rotation: -5.0, offset: CGSize(width: 0, height: -4), scaleX: 1.04, scaleY: 0.96, duration: 0.12, sprite: "DaddyDead"),
                AnimationStep(rotation: 90.0, offset: CGSize(width: 20, height: 8), scaleX: 1.0, scaleY: 1.0, duration: 0.25),
                AnimationStep(rotation: 90.0, offset: CGSize(width: 20, height: 8), scaleX: 1.0, scaleY: 1.0, duration: 2.0),
                AnimationStep(rotation: 70.0, offset: CGSize(width: 16, height: 6), scaleX: 1.0, scaleY: 1.0, duration: 0.2),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -6), scaleX: 0.96, scaleY: 1.06, duration: 0.18),
                AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.15),
            ]
        case .spin:
            useFollowThrough = false
            steps = [
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 4), scaleX: 1.08, scaleY: 0.92, duration: 0.1),
                AnimationStep(rotation: 360.0, offset: CGSize(width: 0, height: -15), scaleX: 0.96, scaleY: 1.04, duration: 0.3),
                AnimationStep(rotation: 720.0, offset: CGSize(width: 0, height: -10), scaleX: 0.98, scaleY: 1.02, duration: 0.28),
                AnimationStep(rotation: 720.0, offset: CGSize(width: 0, height: 5), scaleX: 1.1, scaleY: 0.9, duration: 0.1),
                AnimationStep(rotation: 725.0, offset: CGSize(width: 3, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.15, sprite: "DaddyDizzy"),
                AnimationStep(rotation: 715.0, offset: CGSize(width: -3, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.15),
                AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.18),
            ]
        case .crabRave:
            useFollowThrough = false
            steps = [
                AnimationStep(rotation: -10.0, offset: CGSize(width: -6, height: -2), scaleX: 1.04, scaleY: 0.98, duration: 0.08, sprite: "DaddyExcited"),
                AnimationStep(rotation: 10.0, offset: CGSize(width: 6, height: -2), scaleX: 1.04, scaleY: 0.98, duration: 0.08),
                AnimationStep(rotation: -12.0, offset: CGSize(width: -8, height: -4), scaleX: 1.06, scaleY: 0.96, duration: 0.08),
                AnimationStep(rotation: 12.0, offset: CGSize(width: 8, height: -4), scaleX: 1.06, scaleY: 0.96, duration: 0.08),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 6), scaleX: 1.12, scaleY: 0.88, duration: 0.1),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -14), scaleX: 0.94, scaleY: 1.14, duration: 0.16),
                AnimationStep(rotation: -14.0, offset: CGSize(width: -8, height: -2), scaleX: 1.06, scaleY: 0.96, duration: 0.08),
                AnimationStep(rotation: 14.0, offset: CGSize(width: 8, height: -2), scaleX: 1.06, scaleY: 0.96, duration: 0.08),
                AnimationStep(rotation: -10.0, offset: CGSize(width: -6, height: 0), scaleX: 1.04, scaleY: 0.98, duration: 0.08),
                AnimationStep(rotation: 10.0, offset: CGSize(width: 6, height: 0), scaleX: 1.04, scaleY: 0.98, duration: 0.08),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -10), scaleX: 0.96, scaleY: 1.08, duration: 0.14),
                AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.16),
            ]
        case .nod:
            steps = [
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 3), scaleX: 1.02, scaleY: 0.98, duration: 0.1),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -2), scaleX: 0.99, scaleY: 1.02, duration: 0.1),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: 2), scaleX: 1.01, scaleY: 0.99, duration: 0.1),
                AnimationStep(rotation: 0.0, offset: CGSize(width: 0, height: -1), scaleX: 1.0, scaleY: 1.01, duration: 0.1),
            ]
        case .shake:
            steps = [
                AnimationStep(rotation: -6.0, offset: CGSize(width: -4, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.08),
                AnimationStep(rotation: 6.0, offset: CGSize(width: 4, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.08),
                AnimationStep(rotation: -5.0, offset: CGSize(width: -3, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.08),
                AnimationStep(rotation: 5.0, offset: CGSize(width: 3, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.08),
                AnimationStep(rotation: -2.0, offset: CGSize(width: -1, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.08),
                AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.1),
            ]
        case .bow:
            useFollowThrough = false
            steps = [
                AnimationStep(rotation: 12.0, offset: CGSize(width: 0, height: 6), scaleX: 1.0, scaleY: 0.92, duration: 0.2),
                AnimationStep(rotation: 12.0, offset: CGSize(width: 0, height: 6), scaleX: 1.0, scaleY: 0.92, duration: 0.5),
                AnimationStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.2),
            ]
        case .none:
            steps = []
        }
        runSequence(steps, requireIdle: false, followThrough: useFollowThrough)
    }
}
