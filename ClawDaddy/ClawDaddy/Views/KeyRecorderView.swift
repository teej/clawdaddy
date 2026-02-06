import AppKit
import SwiftUI

struct KeyRecorderView: NSViewRepresentable {
    @Binding var capturedKey: PTTKey?

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onCapture = { key in
            DispatchQueue.main.async { capturedKey = key }
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {}

    final class KeyCaptureView: NSView {
        var onCapture: ((PTTKey) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            let code = event.keyCode
            guard !PTTKey.rejectedKeyCodes.contains(code) else {
                NSSound.beep()
                return
            }
            guard PTTKey.modifierKeyCodes[code] == nil else { return }

            let name = PTTKey.displayName(forKeyCode: code)
            onCapture?(PTTKey(keyCode: code, isModifier: false, modifierFlag: nil, displayName: name))
        }

        override func flagsChanged(with event: NSEvent) {
            let code = event.keyCode
            guard !PTTKey.rejectedKeyCodes.contains(code) else {
                NSSound.beep()
                return
            }
            guard let flag = PTTKey.modifierKeyCodes[code] else { return }

            // Only capture on press (flag set), not release
            guard event.modifierFlags.contains(flag) else { return }

            let name = PTTKey.displayName(forKeyCode: code)
            onCapture?(PTTKey(keyCode: code, isModifier: true, modifierFlag: flag.rawValue, displayName: name))
        }
    }
}
