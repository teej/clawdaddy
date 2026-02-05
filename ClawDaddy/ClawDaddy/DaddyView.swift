import SwiftUI

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

enum EmoteStyle: Int {
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

struct DaddyView: View {
    let state: String
    let size: CGFloat
    let jumpTrigger: Int
    let ackStyle: AckStyle
    let reactionStyle: ReactionStyle
    let reactionTrigger: Int
    let saluteTrigger: Int
    let emoteStyle: EmoteStyle
    let emoteTrigger: Int
    let danceTrigger: Int
    let isTalking: Bool

    @State private var breathPhase = false
    @State private var didStartBreathing = false
    @State private var idleOffset = CGSize.zero
    @State private var idleRotation: Double = 0
    @State private var idleScaleX: CGFloat = 1.0
    @State private var idleScaleY: CGFloat = 1.0
    @State private var isPlayingVariant = false
    @State private var viewState = "idle"
    @State private var idleTask: Task<Void, Never>?
    @State private var thinkingTask: Task<Void, Never>?
    @State private var thinkingMotionTask: Task<Void, Never>?
    @State private var listeningPhase = false
    @State private var thinkingPhase = false
    @State private var isSaluting = false
    @State private var spriteOverride: String?
    @State private var spriteOverrideToken = 0
    @State private var talkTask: Task<Void, Never>?
    @State private var talkMouthOpen = false
    @State private var waitingPhase = false
    @State private var waitingTask: Task<Void, Never>?

    var body: some View {
        Image(currentImageName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .scaleEffect(x: finalScaleX, y: finalScaleY, anchor: animationPivot)
            .rotationEffect(finalRotation, anchor: animationPivot)
            .offset(finalOffset)
            .shadow(color: glowColor, radius: glowRadius)
            .animation(.easeInOut(duration: 0.2), value: viewState)
            .onAppear {
                if !didStartBreathing {
                    didStartBreathing = true
                    viewState = state
                    startBreathing()
                    startIdleLoop()
                    if state == "thinking" {
                        startThinkingMotion()
                        startThinkingLoop()
                    }
                }
            }
            .onDisappear {
                idleTask?.cancel()
                idleTask = nil
                thinkingTask?.cancel()
                thinkingTask = nil
                thinkingMotionTask?.cancel()
                thinkingMotionTask = nil
                talkTask?.cancel()
                talkTask = nil
                waitingTask?.cancel()
                waitingTask = nil
            }
            .onChange(of: state) { _, newValue in
                let wasSleeping = viewState == "sleeping"
                viewState = newValue
                if newValue != "idle" && newValue != "sleeping" {
                    resetIdleVariant()
                    isPlayingVariant = false
                }
                if newValue == "listening" {
                    if wasSleeping {
                        playWakeUp()
                    }
                    startListeningMotion()
                } else {
                    listeningPhase = false
                }
                if newValue == "thinking" {
                    startThinkingMotion()
                    startThinkingLoop()
                } else {
                    thinkingPhase = false
                    thinkingTask?.cancel()
                    thinkingTask = nil
                    thinkingMotionTask?.cancel()
                    thinkingMotionTask = nil
                }
                if newValue != "speaking" {
                    stopTalkCycling()
                }
                if newValue == "waiting_for_input" {
                    startWaitingMotion()
                } else {
                    waitingPhase = false
                    waitingTask?.cancel()
                    waitingTask = nil
                }
            }
            .onChange(of: jumpTrigger) { _ in
                playAcknowledge(style: ackStyle)
            }
            .onChange(of: reactionTrigger) { _ in
                playReaction(style: reactionStyle)
            }
            .onChange(of: saluteTrigger) { _ in
                playSalute()
            }
            .onChange(of: emoteTrigger) { _ in
                playEmote(style: emoteStyle)
            }
            .onChange(of: danceTrigger) { _ in
                playDance()
            }
            .onChange(of: isTalking) { _, newValue in
                if newValue && isSpeaking {
                    startTalkCycling()
                } else {
                    stopTalkCycling()
                }
            }
    }

    private var isListening: Bool {
        state == "listening"
    }

    private var isThinking: Bool {
        state == "thinking"
    }

    private var isSpeaking: Bool {
        state == "speaking"
    }

    private var isWaiting: Bool {
        state == "waiting_for_input"
    }

    private var isSleeping: Bool {
        state == "sleeping"
    }

    private var animationPivot: UnitPoint {
        .center
    }

    private var currentImageName: String {
        if let spriteOverride {
            return spriteOverride
        }
        if isSaluting {
            return "DaddySalute"
        }
        if isSpeaking && talkMouthOpen {
            return "DaddyTalk"
        }
        return "Daddy"
    }

    private var breathScale: CGFloat {
        let amplitude: CGFloat = isSleeping ? 0.004 : 0.008
        return breathPhase ? (1.0 + amplitude) : (1.0 - amplitude)
    }

    private var breathRotation: Double {
        guard viewState == "idle" || viewState == "sleeping" else { return 0 }
        let amplitude = isSleeping ? 0.15 : 0.25
        return breathPhase ? amplitude : -amplitude
    }

    private var listeningScale: CGFloat {
        isListening ? 1.03 : 1.0
    }

    private var thinkingScale: CGFloat {
        guard isThinking, !isPlayingVariant else { return 1.0 }
        return thinkingPhase ? 1.01 : 0.99
    }

    private var finalScaleX: CGFloat {
        breathScale * idleScaleX * listeningScale * thinkingScale * speakingScaleX
    }

    private var finalScaleY: CGFloat {
        breathScale * idleScaleY * listeningScale * thinkingScale * speakingScaleY
    }

    private var finalRotation: Angle {
        Angle(degrees: idleRotation + listeningRotation + thinkingRotation + breathRotation + speakingRotation + waitingRotation)
    }

    private var finalOffset: CGSize {
        let listenOffset = CGSize(width: 0, height: isListening ? -2 : 0)
        return CGSize(
            width: idleOffset.width + listenOffset.width + listeningOffset.width + thinkingOffset.width + speakingOffset.width + waitingOffset.width,
            height: idleOffset.height + listenOffset.height + listeningOffset.height + thinkingOffset.height + speakingOffset.height + waitingOffset.height
        )
    }

    private var glowColor: Color {
        if isListening {
            return Color.green.opacity(0.85)
        }
        if isWaiting {
            return Color.orange.opacity(0.5)
        }
        return Color.clear
    }

    private var glowRadius: CGFloat {
        if isListening || isWaiting {
            return 3
        }
        return 0
    }

    private var listeningRotation: Double {
        guard isListening else { return 0 }
        return listeningPhase ? 1.2 : -1.2
    }

    private var thinkingRotation: Double {
        guard isThinking, !isPlayingVariant else { return 0 }
        return thinkingPhase ? 1.5 : -1.5
    }

    private var listeningOffset: CGSize {
        guard isListening else { return .zero }
        return listeningPhase ? CGSize(width: 0, height: 1) : CGSize(width: 0, height: -1)
    }

    private var thinkingOffset: CGSize {
        guard isThinking, !isPlayingVariant else { return .zero }
        return thinkingPhase ? CGSize(width: 1, height: 3) : CGSize(width: -1, height: -3)
    }

    private var speakingScaleX: CGFloat {
        guard isSpeaking else { return 1.0 }
        return talkMouthOpen ? 1.01 : 0.995
    }

    private var speakingScaleY: CGFloat {
        guard isSpeaking else { return 1.0 }
        return talkMouthOpen ? 0.985 : 1.005
    }

    private var speakingOffset: CGSize {
        guard isSpeaking else { return .zero }
        return talkMouthOpen ? CGSize(width: 0, height: 1.5) : CGSize(width: 0, height: -0.5)
    }

    private var speakingRotation: Double {
        guard isSpeaking else { return 0 }
        return talkMouthOpen ? 0.4 : -0.4
    }

    private var waitingRotation: Double {
        guard isWaiting, !isPlayingVariant else { return 0 }
        return waitingPhase ? 2.0 : -2.0
    }

    private var waitingOffset: CGSize {
        guard isWaiting, !isPlayingVariant else { return .zero }
        return waitingPhase ? CGSize(width: 2, height: 0) : CGSize(width: -2, height: 0)
    }

    private func startBreathing() {
        breathPhase = false
        withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
            breathPhase = true
        }
    }

    private func startIdleLoop() {
        idleTask?.cancel()
        idleTask = Task {
            while !Task.isCancelled {
                let sleeping = await MainActor.run { viewState == "sleeping" }
                let delay = sleeping
                    ? Double.random(in: 30.0...60.0)
                    : Double.random(in: 12.0...20.0)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await MainActor.run {
                    if viewState == "sleeping" {
                        playSleepyBob()
                    } else if viewState == "idle" {
                        playIdleVariant()
                    }
                }
            }
        }
    }

    private func startListeningMotion() {
        // Anticipation squash — quick duck before listening sway
        withAnimation(.easeOut(duration: 0.08)) {
            idleScaleX = 1.06
            idleScaleY = 0.94
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.08)) {
                idleScaleX = 1.0
                idleScaleY = 1.0
            }
        }
        listeningPhase = false
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            listeningPhase = true
        }
    }

    private func startThinkingMotion() {
        thinkingMotionTask?.cancel()
        thinkingPhase = false
        thinkingMotionTask = Task {
            while !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 1.2)) {
                        thinkingPhase.toggle()
                    }
                }
                try? await Task.sleep(nanoseconds: 1_150_000_000)
            }
        }
    }

    private func startThinkingLoop() {
        thinkingTask?.cancel()
        thinkingTask = Task {
            while !Task.isCancelled {
                let delay = Double.random(in: 2.0...3.6)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await MainActor.run {
                    guard isThinking, !isPlayingVariant else { return }
                    let hold = Double.random(in: 0.9...1.3)
                    flashSprite("DaddyThinking", duration: hold)
                }
            }
        }
    }

    private func startTalkCycling() {
        talkMouthOpen = false
        talkTask?.cancel()
        talkTask = Task {
            while !Task.isCancelled {
                await MainActor.run {
                    talkMouthOpen.toggle()
                }
                let interval = UInt64.random(in: 120_000_000...180_000_000)
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func stopTalkCycling() {
        talkTask?.cancel()
        talkTask = nil
        talkMouthOpen = false
    }

    private func startWaitingMotion() {
        waitingTask?.cancel()
        waitingPhase = false
        waitingTask = Task {
            while !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        waitingPhase.toggle()
                    }
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    private func playIdleVariant() {
        if isPlayingVariant {
            return
        }
        let roll = Double.random(in: 0...1)
        if roll < 0.03 {
            // Ultra-rare spontaneous mischief
            playEmote(style: .plank)
        } else if roll < 0.15 {
            playRareIdle()
        } else if roll < 0.55 {
            playCommonIdle()
        }
    }

    private struct IdleStep {
        let rotation: Double
        let offset: CGSize
        let scaleX: CGFloat
        let scaleY: CGFloat
        let duration: Double
    }

    private func runSequence(_ steps: [IdleStep], requireIdle: Bool, includeFollowThrough: Bool = false) {
        var sequence = steps
        if includeFollowThrough {
            sequence.append(contentsOf: followThroughSteps)
        }

        var delay: Double = 0
        for step in sequence {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if requireIdle && viewState != "idle" && viewState != "sleeping" {
                    return
                }
                guard isPlayingVariant else { return }
                withAnimation(stepAnimation(step.duration)) {
                    idleRotation = step.rotation
                    idleOffset = step.offset
                    idleScaleX = step.scaleX
                    idleScaleY = step.scaleY
                }
            }
            delay += step.duration
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if !requireIdle || viewState == "idle" || viewState == "sleeping" {
                resetIdleVariant()
            }
            isPlayingVariant = false
        }
    }

    private func stepAnimation(_ duration: Double) -> Animation {
        Animation.timingCurve(0.22, 0.61, 0.36, 1.0, duration: duration)
    }

    private var followThroughSteps: [IdleStep] {
        [
            IdleStep(rotation: 1.4, offset: CGSize(width: 1, height: -1), scaleX: 1.01, scaleY: 0.99, duration: 0.12),
            IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.16),
        ]
    }

    private func flashSprite(_ name: String, duration: Double) {
        spriteOverrideToken += 1
        let token = spriteOverrideToken
        spriteOverride = name
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if spriteOverrideToken == token {
                spriteOverride = nil
            }
        }
    }

    private func playCommonIdle() {
        isPlayingVariant = true
        let choice = Int.random(in: 0...2)
        switch choice {
        case 0:
            playDrift()
        case 1:
            playSoftBob()
        default:
            playStretch()
        }
    }

    private func playRareIdle() {
        isPlayingVariant = true
        let choice = Int.random(in: 0...4)
        switch choice {
        case 0:
            playAnchorDrop()
        case 1:
            playProudSwing()
        case 2:
            playHeadTilt()
        case 3:
            playPeek()
        default:
            playShimmy()
        }
    }

    private func playDrift() {
        runSequence(
            [
                IdleStep(rotation: -1.6, offset: CGSize(width: -2, height: 1), scaleX: 1.01, scaleY: 0.99, duration: 0.4),
                IdleStep(rotation: 1.8, offset: CGSize(width: 2, height: 0), scaleX: 1.01, scaleY: 0.99, duration: 0.45),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.35),
            ],
            requireIdle: true
        )
    }

    private func playSoftBob() {
        runSequence(
            [
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 2), scaleX: 1.02, scaleY: 0.98, duration: 0.3),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -3), scaleX: 0.99, scaleY: 1.03, duration: 0.36),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 1), scaleX: 1.01, scaleY: 0.99, duration: 0.24),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.28),
            ],
            requireIdle: true
        )
    }

    private func playAnchorDrop() {
        runSequence(
            [
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 6), scaleX: 1.08, scaleY: 0.9, duration: 0.16),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -8), scaleX: 0.96, scaleY: 1.08, duration: 0.2),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 3), scaleX: 1.04, scaleY: 0.96, duration: 0.18),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.24),
            ],
            requireIdle: true,
            includeFollowThrough: true
        )
    }

    private func playProudSwing() {
        runSequence(
            [
                IdleStep(rotation: -7.0, offset: CGSize(width: -4, height: 0), scaleX: 1.04, scaleY: 0.98, duration: 0.18),
                IdleStep(rotation: 7.0, offset: CGSize(width: 4, height: 0), scaleX: 1.04, scaleY: 0.98, duration: 0.18),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -4), scaleX: 1.06, scaleY: 0.97, duration: 0.2),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.26),
            ],
            requireIdle: true,
            includeFollowThrough: true
        )
    }

    private func playHeadTilt() {
        flashSprite("DaddyTilt", duration: 0.7)
        runSequence(
            [
                IdleStep(rotation: -6.0, offset: CGSize(width: -2, height: 1), scaleX: 1.02, scaleY: 0.98, duration: 0.2),
                IdleStep(rotation: 4.0, offset: CGSize(width: 2, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.2),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -2), scaleX: 1.01, scaleY: 0.99, duration: 0.22),
            ],
            requireIdle: true,
            includeFollowThrough: true
        )
    }

    private func playStretch() {
        runSequence(
            [
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -5), scaleX: 0.96, scaleY: 1.06, duration: 0.3),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -3), scaleX: 0.97, scaleY: 1.04, duration: 0.4),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 3), scaleX: 1.04, scaleY: 0.97, duration: 0.2),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.25),
            ],
            requireIdle: true,
            includeFollowThrough: true
        )
    }

    private func playPeek() {
        runSequence(
            [
                IdleStep(rotation: -4.0, offset: CGSize(width: -6, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.2),
                IdleStep(rotation: -6.0, offset: CGSize(width: -10, height: -2), scaleX: 1.0, scaleY: 1.0, duration: 0.3),
                IdleStep(rotation: -4.0, offset: CGSize(width: -6, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.15),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.2),
            ],
            requireIdle: true,
            includeFollowThrough: true
        )
    }

    private func playShimmy() {
        runSequence(
            [
                IdleStep(rotation: -3.0, offset: CGSize(width: -2, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.1),
                IdleStep(rotation: 3.0, offset: CGSize(width: 2, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.1),
                IdleStep(rotation: -2.0, offset: CGSize(width: -1, height: 0), scaleX: 1.01, scaleY: 0.99, duration: 0.1),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.15),
            ],
            requireIdle: true
        )
    }

    private func playAcknowledge(style: AckStyle) {
        resetIdleVariant()
        isPlayingVariant = true
        let saluteSteps: [IdleStep] = [
            IdleStep(rotation: -2.0, offset: CGSize(width: 0, height: 4), scaleX: 1.03, scaleY: 0.97, duration: 0.1),
            IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.08),
        ]
        flashSprite("DaddySalute", duration: 0.24)

        let bounceSteps: [IdleStep]
        switch style {
        case .big:
            bounceSteps = [
                IdleStep(rotation: -2.0, offset: CGSize(width: 0, height: 8), scaleX: 1.14, scaleY: 0.88, duration: 0.08),
                IdleStep(rotation: 2.0, offset: CGSize(width: 0, height: -20), scaleX: 0.94, scaleY: 1.16, duration: 0.18),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 7), scaleX: 1.08, scaleY: 0.92, duration: 0.12),
                IdleStep(rotation: -1.0, offset: CGSize(width: 0, height: -12), scaleX: 0.97, scaleY: 1.08, duration: 0.16),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 3), scaleX: 1.03, scaleY: 0.97, duration: 0.12),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.2),
            ]
        case .standard:
            bounceSteps = [
                IdleStep(rotation: -1.0, offset: CGSize(width: 0, height: 6), scaleX: 1.1, scaleY: 0.9, duration: 0.08),
                IdleStep(rotation: 1.0, offset: CGSize(width: 0, height: -16), scaleX: 0.95, scaleY: 1.12, duration: 0.18),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 5), scaleX: 1.06, scaleY: 0.94, duration: 0.12),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -9), scaleX: 0.98, scaleY: 1.06, duration: 0.16),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 2), scaleX: 1.02, scaleY: 0.98, duration: 0.12),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.2),
            ]
        }
        runSequence(saluteSteps + bounceSteps, requireIdle: false, includeFollowThrough: true)
    }

    private func playDance() {
        resetIdleVariant()
        isPlayingVariant = true
        flashSprite("DaddyExcited", duration: 1.0)
        runSequence(
            [
                IdleStep(rotation: -8.0, offset: CGSize(width: -4, height: 0), scaleX: 1.04, scaleY: 0.98, duration: 0.12),
                IdleStep(rotation: 8.0, offset: CGSize(width: 4, height: 0), scaleX: 1.04, scaleY: 0.98, duration: 0.12),
                IdleStep(rotation: -12.0, offset: CGSize(width: -6, height: -2), scaleX: 1.08, scaleY: 0.94, duration: 0.14),
                IdleStep(rotation: 12.0, offset: CGSize(width: 6, height: -2), scaleX: 1.08, scaleY: 0.94, duration: 0.14),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 5), scaleX: 1.12, scaleY: 0.9, duration: 0.12),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -12), scaleX: 0.95, scaleY: 1.12, duration: 0.18),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 4), scaleX: 1.06, scaleY: 0.96, duration: 0.12),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.2),
            ],
            requireIdle: false,
            includeFollowThrough: true
        )
    }

    private func playReaction(style: ReactionStyle) {
        guard style != .none else { return }
        guard !isPlayingVariant else { return }
        resetIdleVariant()
        isPlayingVariant = true
        let steps: [IdleStep]
        switch style {
        case .perk:
            steps = [
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 3), scaleX: 1.04, scaleY: 0.96, duration: 0.1),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -6), scaleX: 0.98, scaleY: 1.05, duration: 0.16),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 2), scaleX: 1.02, scaleY: 0.98, duration: 0.12),
            ]
        case .settle:
            steps = [
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 4), scaleX: 1.05, scaleY: 0.95, duration: 0.14),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -2), scaleX: 0.99, scaleY: 1.02, duration: 0.14),
            ]
        case .alert:
            flashSprite("DaddySurprised", duration: 0.5)
            steps = [
                IdleStep(rotation: -4.0, offset: CGSize(width: -2, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.1),
                IdleStep(rotation: 4.0, offset: CGSize(width: 2, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.1),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.12),
            ]
        case .none:
            steps = []
        }
        runSequence(steps, requireIdle: false, includeFollowThrough: true)
    }

    private func playSalute() {
        resetIdleVariant()
        isPlayingVariant = true
        isSaluting = true
        let saluteHold: Double = 1.4
        flashSprite("DaddySalute", duration: saluteHold)
        let steps = [
            IdleStep(rotation: -2.0, offset: CGSize(width: 0, height: 5), scaleX: 1.04, scaleY: 0.96, duration: 0.12),
            IdleStep(rotation: 2.0, offset: CGSize(width: 0, height: -6), scaleX: 0.98, scaleY: 1.05, duration: 0.18),
            IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 2), scaleX: 1.02, scaleY: 0.98, duration: 0.16),
            IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.2),
        ]
        runSequence(steps, requireIdle: false, includeFollowThrough: true)

        let total = steps.reduce(0.0) { $0 + $1.duration }
        let releaseDelay = max(saluteHold, total + 0.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + releaseDelay) {
            isSaluting = false
        }
    }

    private func playSleepyBob() {
        if isPlayingVariant { return }
        isPlayingVariant = true
        runSequence(
            [
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 1), scaleX: 1.01, scaleY: 0.99, duration: 0.5),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -1), scaleX: 0.99, scaleY: 1.01, duration: 0.6),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.4),
            ],
            requireIdle: true
        )
    }

    private func playWakeUp() {
        resetIdleVariant()
        isPlayingVariant = true
        flashSprite("DaddySurprised", duration: 0.3)
        runSequence(
            [
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -8), scaleX: 0.96, scaleY: 1.08, duration: 0.12),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -4), scaleX: 0.95, scaleY: 1.1, duration: 0.2),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.16),
            ],
            requireIdle: false,
            includeFollowThrough: true
        )
    }

    private func playEmote(style: EmoteStyle) {
        guard style != .none else { return }
        guard !isPlayingVariant else { return }
        resetIdleVariant()
        isPlayingVariant = true
        var useFollowThrough = true
        let steps: [IdleStep]
        switch style {
        case .wink:
            flashSprite("DaddyWink", duration: 0.35)
            steps = [
                IdleStep(rotation: -2.0, offset: CGSize(width: 0, height: 4), scaleX: 1.04, scaleY: 0.96, duration: 0.12),
                IdleStep(rotation: 1.0, offset: CGSize(width: 0, height: -5), scaleX: 0.99, scaleY: 1.03, duration: 0.16),
            ]
        case .tilt:
            flashSprite("DaddyTilt", duration: 0.7)
            steps = [
                IdleStep(rotation: -5.0, offset: CGSize(width: -2, height: 2), scaleX: 1.02, scaleY: 0.98, duration: 0.2),
                IdleStep(rotation: 3.0, offset: CGSize(width: 2, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.2),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -1), scaleX: 1.01, scaleY: 0.99, duration: 0.2),
            ]
        case .surprised:
            flashSprite("DaddySurprised", duration: 0.45)
            steps = [
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 6), scaleX: 1.06, scaleY: 0.94, duration: 0.12),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -8), scaleX: 0.98, scaleY: 1.08, duration: 0.18),
            ]
        case .backflip:
            useFollowThrough = false
            steps = [
                // Squash anticipation
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 6), scaleX: 1.12, scaleY: 0.88, duration: 0.12),
                // Launch up + 180° spin
                IdleStep(rotation: 180.0, offset: CGSize(width: 0, height: -30), scaleX: 0.95, scaleY: 1.05, duration: 0.28),
                // Continue to 360° coming down
                IdleStep(rotation: 360.0, offset: CGSize(width: 0, height: -8), scaleX: 1.0, scaleY: 1.0, duration: 0.24),
                // Landing squash
                IdleStep(rotation: 360.0, offset: CGSize(width: 0, height: 5), scaleX: 1.1, scaleY: 0.9, duration: 0.1),
                // Settle back to neutral
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.18),
            ]
        case .plank:
            useFollowThrough = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [self] in
                flashSprite("DaddySurprised", duration: 0.55)
            }
            steps = [
                IdleStep(rotation: 4.0, offset: CGSize(width: 10, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.2),
                IdleStep(rotation: 6.0, offset: CGSize(width: 200, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.3),
                IdleStep(rotation: 6.0, offset: CGSize(width: 200, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.6),
                IdleStep(rotation: -4.0, offset: CGSize(width: 120, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.25),
                IdleStep(rotation: -4.0, offset: CGSize(width: 120, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.3),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.3),
            ]
        case .playDead:
            useFollowThrough = false
            flashSprite("DaddyDead", duration: 2.8)
            steps = [
                // Startled lean
                IdleStep(rotation: -5.0, offset: CGSize(width: 0, height: -4), scaleX: 1.04, scaleY: 0.96, duration: 0.12),
                // Fall sideways
                IdleStep(rotation: 90.0, offset: CGSize(width: 20, height: 8), scaleX: 1.0, scaleY: 1.0, duration: 0.25),
                // Hold dead
                IdleStep(rotation: 90.0, offset: CGSize(width: 20, height: 8), scaleX: 1.0, scaleY: 1.0, duration: 2.0),
                // Peek (slight rotation back)
                IdleStep(rotation: 70.0, offset: CGSize(width: 16, height: 6), scaleX: 1.0, scaleY: 1.0, duration: 0.2),
                // Pop back up
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -6), scaleX: 0.96, scaleY: 1.06, duration: 0.18),
                // Settle
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.15),
            ]
        case .spin:
            useFollowThrough = false
            // Flash dizzy sprite after the spin lands (0.78s in), lasting through wobble + settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.78) { [self] in
                flashSprite("DaddyDizzy", duration: 0.48)
            }
            steps = [
                // Anticipation squash
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 4), scaleX: 1.08, scaleY: 0.92, duration: 0.1),
                // First 360
                IdleStep(rotation: 360.0, offset: CGSize(width: 0, height: -15), scaleX: 0.96, scaleY: 1.04, duration: 0.3),
                // Second 360 (720 total)
                IdleStep(rotation: 720.0, offset: CGSize(width: 0, height: -10), scaleX: 0.98, scaleY: 1.02, duration: 0.28),
                // Landing squash
                IdleStep(rotation: 720.0, offset: CGSize(width: 0, height: 5), scaleX: 1.1, scaleY: 0.9, duration: 0.1),
                // Dizzy wobble
                IdleStep(rotation: 725.0, offset: CGSize(width: 3, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.15),
                IdleStep(rotation: 715.0, offset: CGSize(width: -3, height: 0), scaleX: 1.02, scaleY: 0.98, duration: 0.15),
                // Settle
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.18),
            ]
        case .crabRave:
            useFollowThrough = false
            flashSprite("DaddyExcited", duration: 1.1)
            steps = [
                // Rapid shimmy
                IdleStep(rotation: -10.0, offset: CGSize(width: -6, height: -2), scaleX: 1.04, scaleY: 0.98, duration: 0.08),
                IdleStep(rotation: 10.0, offset: CGSize(width: 6, height: -2), scaleX: 1.04, scaleY: 0.98, duration: 0.08),
                IdleStep(rotation: -12.0, offset: CGSize(width: -8, height: -4), scaleX: 1.06, scaleY: 0.96, duration: 0.08),
                IdleStep(rotation: 12.0, offset: CGSize(width: 8, height: -4), scaleX: 1.06, scaleY: 0.96, duration: 0.08),
                // Big bounce
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 6), scaleX: 1.12, scaleY: 0.88, duration: 0.1),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -14), scaleX: 0.94, scaleY: 1.14, duration: 0.16),
                // More shimmy
                IdleStep(rotation: -14.0, offset: CGSize(width: -8, height: -2), scaleX: 1.06, scaleY: 0.96, duration: 0.08),
                IdleStep(rotation: 14.0, offset: CGSize(width: 8, height: -2), scaleX: 1.06, scaleY: 0.96, duration: 0.08),
                IdleStep(rotation: -10.0, offset: CGSize(width: -6, height: 0), scaleX: 1.04, scaleY: 0.98, duration: 0.08),
                IdleStep(rotation: 10.0, offset: CGSize(width: 6, height: 0), scaleX: 1.04, scaleY: 0.98, duration: 0.08),
                // Flourish
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -10), scaleX: 0.96, scaleY: 1.08, duration: 0.14),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.16),
            ]
        case .nod:
            steps = [
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 3), scaleX: 1.02, scaleY: 0.98, duration: 0.1),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -2), scaleX: 0.99, scaleY: 1.02, duration: 0.1),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: 2), scaleX: 1.01, scaleY: 0.99, duration: 0.1),
                IdleStep(rotation: 0.0, offset: CGSize(width: 0, height: -1), scaleX: 1.0, scaleY: 1.01, duration: 0.1),
            ]
        case .shake:
            steps = [
                IdleStep(rotation: -6.0, offset: CGSize(width: -4, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.08),
                IdleStep(rotation: 6.0, offset: CGSize(width: 4, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.08),
                IdleStep(rotation: -5.0, offset: CGSize(width: -3, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.08),
                IdleStep(rotation: 5.0, offset: CGSize(width: 3, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.08),
                IdleStep(rotation: -2.0, offset: CGSize(width: -1, height: 0), scaleX: 1.0, scaleY: 1.0, duration: 0.08),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.1),
            ]
        case .bow:
            useFollowThrough = false
            steps = [
                IdleStep(rotation: 12.0, offset: CGSize(width: 0, height: 6), scaleX: 1.0, scaleY: 0.92, duration: 0.2),
                IdleStep(rotation: 12.0, offset: CGSize(width: 0, height: 6), scaleX: 1.0, scaleY: 0.92, duration: 0.5),
                IdleStep(rotation: 0.0, offset: .zero, scaleX: 1.0, scaleY: 1.0, duration: 0.2),
            ]
        case .none:
            steps = []
        }
        runSequence(steps, requireIdle: false, includeFollowThrough: useFollowThrough)
    }

    private func resetIdleVariant() {
        idleRotation = 0
        idleOffset = .zero
        idleScaleX = 1.0
        idleScaleY = 1.0
    }
}
