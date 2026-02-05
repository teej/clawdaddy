import SwiftUI

struct DaddyView: View {
    let model: DaddyAnimationModel
    let size: CGFloat

    @State private var lastHoverReaction = Date.distantPast

    var body: some View {
        Image(model.currentImageName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .scaleEffect(x: model.finalScaleX, y: model.finalScaleY, anchor: .center)
            .rotationEffect(model.finalRotation, anchor: .center)
            .offset(model.finalOffset)
            .shadow(color: model.glowColor, radius: model.glowRadius)
            .animation(.easeInOut(duration: 0.2), value: model.animState)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                    let now = Date()
                    if now.timeIntervalSince(lastHoverReaction) >= 3.0 {
                        lastHoverReaction = now
                        model.send(.reaction(.perk))
                    }
                } else {
                    NSCursor.pop()
                }
            }
            .onTapGesture(count: 2) {
                model.send(.randomEmote)
            }
            .contextMenu {
                Button("Dance") { model.send(.dance) }
                Button("Salute") { model.send(.salute) }
                Divider()
                Menu("Emotes") {
                    Button("Wink") { model.send(.emote(.wink)) }
                    Button("Backflip") { model.send(.emote(.backflip)) }
                    Button("Spin") { model.send(.emote(.spin)) }
                    Button("Crab Rave") { model.send(.emote(.crabRave)) }
                    Button("Play Dead") { model.send(.emote(.playDead)) }
                    Button("Bow") { model.send(.emote(.bow)) }
                }
                Divider()
                Button("About ClawDaddy") {
                    // Placeholder — version/flavor text
                }
            }
            .onAppear { model.start() }
            .onDisappear { model.stop() }
    }
}
