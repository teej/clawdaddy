import SwiftUI

struct TypewriterText: View {
    let text: String
    let charsPerSecond: Double
    var onRevealChange: ((Bool) -> Void)?

    @State private var visibleCount = 0
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        Text(text.prefix(visibleCount))
            .onAppear {
                startReveal()
            }
            .onDisappear {
                revealTask?.cancel()
                onRevealChange?(false)
            }
            .onChange(of: text) {
                if text.count > visibleCount {
                    startReveal()
                }
            }
    }

    private func startReveal() {
        revealTask?.cancel()
        let target = text.count
        guard visibleCount < target else { return }
        onRevealChange?(true)
        let interval = UInt64(1_000_000_000 / charsPerSecond)
        revealTask = Task { @MainActor in
            while visibleCount < target, !Task.isCancelled {
                visibleCount += 1
                try? await Task.sleep(nanoseconds: interval)
            }
            onRevealChange?(false)
        }
    }
}

struct SpeechBubbleView: View {
    let text: String
    let isInteractive: Bool
    var typewriter: Bool = false
    var onRevealChange: ((Bool) -> Void)?
    var onTap: () -> Void

    var body: some View {
        let base = bubbleShape
            .fill(Color.white.opacity(0.92))
            .overlay(
                bubbleShape
                    .stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
            )

        let interactiveStroke = bubbleShape
            .stroke(isInteractive ? Color.blue.opacity(0.7) : Color.clear, lineWidth: 1)

        return textContent
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.black)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .padding(12)
            .background(base)
            .overlay(interactiveStroke)
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 2)
            .frame(maxWidth: 280, alignment: .leading)
            .onTapGesture {
                if isInteractive {
                    onTap()
                }
            }
    }

    @ViewBuilder
    private var textContent: some View {
        if typewriter {
            TypewriterText(text: text, charsPerSecond: 60, onRevealChange: onRevealChange)
        } else {
            Text(text)
        }
    }

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12)
    }
}
