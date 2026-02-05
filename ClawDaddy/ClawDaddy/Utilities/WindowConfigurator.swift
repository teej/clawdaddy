import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    @Binding var windowSize: CGSize
    let isInteractive: Bool

    func makeNSView(context: Context) -> WindowConfigView {
        let view = WindowConfigView()
        view.onWindowChange = { window in
            configure(window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: WindowConfigView, context: Context) {
        nsView.onWindowChange = { window in
            configure(window, coordinator: context.coordinator)
        }
        if let window = nsView.window {
            configure(window, coordinator: context.coordinator)
        }
    }

    private func configure(_ window: NSWindow, coordinator: Coordinator) {
        if !coordinator.didConfigure {
            coordinator.didConfigure = true

            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.hasShadow = false
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isRestorable = false
            window.setFrameAutosaveName("")

            let targetScreen = NSScreen.main ?? NSScreen.screens.first
            let size = preferredWindowSize(for: targetScreen)
            positionWindow(window, size: size, screen: targetScreen)
            DispatchQueue.main.async {
                if windowSize != size {
                    windowSize = size
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                positionWindow(window, size: size, screen: targetScreen)
            }
        }

        window.ignoresMouseEvents = !isInteractive
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var didConfigure = false
    }

    private func positionWindow(_ window: NSWindow, size: NSSize, screen: NSScreen?) {
        guard let screen else { return }
        window.setContentSize(size)
        let contentRect = NSRect(origin: .zero, size: size)
        let frameRect = window.frameRect(forContentRect: contentRect)
        let frame = screen.visibleFrame
        let insetX: CGFloat = 32
        let insetY: CGFloat = 32
        let origin = NSPoint(
            x: frame.maxX - frameRect.width - insetX,
            y: frame.minY + insetY
        )
        window.setFrame(NSRect(origin: origin, size: frameRect.size), display: true)
    }

    private func preferredWindowSize(for screen: NSScreen?) -> NSSize {
        guard let screen else { return NSSize(width: 320, height: 220) }
        let frame = screen.visibleFrame
        let height = max(220, frame.height * 0.5)
        return NSSize(width: 320, height: height)
    }
}

final class WindowConfigView: NSView {
    var onWindowChange: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindowChange?(window)
        }
    }
}
