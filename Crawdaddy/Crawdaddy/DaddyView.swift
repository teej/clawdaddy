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

    var body: some View {
        Image(currentImageName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .scaleEffect(x: finalScaleX, y: finalScaleY, anchor: animationPivot)
            .opacity(opacity)
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
            }
            .onChange(of: state) { _, newValue in
                viewState = newValue
                if newValue != "idle" {
                    resetIdleVariant()
                    isPlayingVariant = false
                }
                if newValue == "listening" {
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
        return "Daddy"
    }

    private var breathScale: CGFloat {
        breathPhase ? 1.008 : 0.996
    }

    private var breathRotation: Double {
        guard viewState == "idle" else { return 0 }
        return breathPhase ? 0.25 : -0.25
    }

    private var listeningScale: CGFloat {
        isListening ? 1.03 : 1.0
    }

    private var thinkingScale: CGFloat {
        guard isThinking, !isPlayingVariant else { return 1.0 }
        return thinkingPhase ? 1.01 : 0.99
    }

    private var finalScaleX: CGFloat {
        breathScale * idleScaleX * listeningScale * thinkingScale
    }

    private var finalScaleY: CGFloat {
        breathScale * idleScaleY * listeningScale * thinkingScale
    }

    private var opacity: Double {
        if isSpeaking {
            return breathPhase ? 1.0 : 0.92
        }
        return 1.0
    }

    private var finalRotation: Angle {
        Angle(degrees: idleRotation + listeningRotation + thinkingRotation + breathRotation)
    }

    private var finalOffset: CGSize {
        let listenOffset = CGSize(width: 0, height: isListening ? -2 : 0)
        return CGSize(
            width: idleOffset.width + listenOffset.width + listeningOffset.width + thinkingOffset.width,
            height: idleOffset.height + listenOffset.height + listeningOffset.height + thinkingOffset.height
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
        return 0
    }

    private var listeningOffset: CGSize {
        guard isListening else { return .zero }
        return listeningPhase ? CGSize(width: 0, height: 1) : CGSize(width: 0, height: -1)
    }

    private var thinkingOffset: CGSize {
        guard isThinking, !isPlayingVariant else { return .zero }
        return thinkingPhase ? CGSize(width: 0, height: 2) : CGSize(width: 0, height: -2)
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
                let delay = Double.random(in: 12.0...20.0)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await MainActor.run {
                    guard viewState == "idle" else { return }
                    playIdleVariant()
                }
            }
        }
    }

    private func startListeningMotion() {
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

    private func playIdleVariant() {
        if isPlayingVariant {
            return
        }
        let roll = Double.random(in: 0...1)
        if roll < 0.15 {
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
                if requireIdle && viewState != "idle" {
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
            if !requireIdle || viewState == "idle" {
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
        let choice = Int.random(in: 0...1)
        switch choice {
        case 0:
            playDrift()
        default:
            playSoftBob()
        }
    }

    private func playRareIdle() {
        isPlayingVariant = true
        let choice = Int.random(in: 0...2)
        switch choice {
        case 0:
            playAnchorDrop()
        case 1:
            playProudSwing()
        default:
            playHeadTilt()
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

    private func playEmote(style: EmoteStyle) {
        guard style != .none else { return }
        guard !isPlayingVariant else { return }
        resetIdleVariant()
        isPlayingVariant = true
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
        case .none:
            steps = []
        }
        runSequence(steps, requireIdle: false, includeFollowThrough: true)
    }

    private func resetIdleVariant() {
        idleRotation = 0
        idleOffset = .zero
        idleScaleX = 1.0
        idleScaleY = 1.0
    }
}
