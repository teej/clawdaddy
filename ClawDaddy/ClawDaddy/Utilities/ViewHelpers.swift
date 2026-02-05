import SwiftUI

extension View {
    @ViewBuilder
    func debugBorder(_ enabled: Bool, color: Color) -> some View {
        if enabled {
            self.overlay(Rectangle().stroke(color, lineWidth: 1))
        } else {
            self
        }
    }
}

struct BottomRowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
