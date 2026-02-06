import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var onDismiss: () -> Void

    @State private var isRecording = false
    @State private var capturedKey: PTTKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Push-to-Talk Key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if isRecording {
                    ZStack {
                        KeyRecorderView(capturedKey: $capturedKey)
                            .frame(width: 0, height: 0)
                            .opacity(0)

                        Text("Press a key...")
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(.quaternary)
                            .cornerRadius(6)
                    }
                } else {
                    HStack {
                        Text(settings.pttKey.displayName)
                            .font(.system(.body, design: .monospaced))

                        Spacer()

                        Button("Change") {
                            capturedKey = nil
                            isRecording = true
                        }
                    }
                }

                if !settings.pttKey.isModifier {
                    Text("Non-modifier keys require Accessibility permission for global PTT.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            HStack {
                Button("Reset to Default") {
                    settings.resetToDefault()
                    isRecording = false
                }
                .disabled(settings.pttKey == .defaultKey)

                Spacer()

                Button("Done", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onChange(of: capturedKey) { newKey in
            guard let key = newKey else { return }
            settings.pttKey = key
            isRecording = false
        }
    }
}
