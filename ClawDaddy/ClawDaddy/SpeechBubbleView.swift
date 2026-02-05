import SwiftUI

struct SpeechBubbleView: View {
    let text: String
    let isInteractive: Bool
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

        return Text(text)
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

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12)
    }
}
