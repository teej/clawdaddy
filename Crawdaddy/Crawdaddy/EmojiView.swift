import SwiftUI

struct EmojiView: View {
    let emoji: String
    let state: String
    let size: CGFloat
    var showsGlow: Bool = true

    @State private var phase = false

    var body: some View {
        Text(emoji)
            .font(.system(size: size))
            .scaleEffect(scale)
            .opacity(opacity)
            .rotationEffect(rotation)
            .shadow(color: glowColor, radius: glowRadius)
            .animation(animation, value: phase)
            .onAppear {
                startPhase()
            }
            .onChange(of: state) { _, _ in
                startPhase()
            }
    }

    private var isListening: Bool {
        state == "listening"
    }

    private var isSpeaking: Bool {
        state == "speaking"
    }

    private var isWorking: Bool {
        state == "working"
    }

    private var isWaiting: Bool {
        state == "waiting_for_input"
    }

    private var isError: Bool {
        state == "error"
    }

    private var shouldWobble: Bool {
        state == "working" || state == "waiting_for_input" || state == "done" || state == "error"
    }

    private var shouldAnimate: Bool {
        isListening || isSpeaking || shouldWobble
    }

    private var scale: CGFloat {
        if isListening || isWaiting {
            return phase ? 1.08 : 0.98
        }
        return 1.0
    }

    private var opacity: Double {
        if isSpeaking {
            return phase ? 1.0 : 0.8
        }
        return 1.0
    }

    private var rotation: Angle {
        if shouldWobble {
            return phase ? .degrees(6) : .degrees(-6)
        }
        return .zero
    }

    private var glowColor: Color {
        guard showsGlow else { return Color.clear }
        if isListening {
            return Color.green.opacity(0.6)
        }
        if isWaiting {
            return Color.orange.opacity(0.5)
        }
        if isError {
            return Color.red.opacity(0.65)
        }
        return Color.clear
    }

    private var glowRadius: CGFloat {
        guard showsGlow else { return 0 }
        if isListening || isWaiting || isError {
            return phase ? 8 : 3
        }
        return 0
    }

    private var animation: Animation? {
        if shouldAnimate {
            return .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
        }
        return .default
    }

    private func startPhase() {
        if shouldAnimate {
            phase = false
            withAnimation(animation) {
                phase = true
            }
        } else {
            phase = false
        }
    }
}
