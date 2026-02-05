import SwiftUI

struct DaddyView: View {
    let model: DaddyAnimationModel
    let size: CGFloat

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
            .onAppear { model.start() }
            .onDisappear { model.stop() }
    }
}
