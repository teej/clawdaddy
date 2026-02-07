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

            VStack(alignment: .leading, spacing: 8) {
                Text("Speech-to-Text")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Provider", selection: $settings.sttProvider) {
                    Text("Apple").tag(STTProvider.apple)
                    Text("Voxtral").tag(STTProvider.voxtral)
                }
                .pickerStyle(.segmented)

                if settings.sttProvider == .voxtral {
                    SecureField("Mistral API Key", text: $settings.mistralApiKey)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(settings.mistralApiKey.isEmpty ? .red : .green)
                            .frame(width: 8, height: 8)
                        Text(settings.mistralApiKey.isEmpty ? "API key required" : "API key set")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Toggle("Use Foundation Models (when available)", isOn: $settings.useFoundationModels)
                .toggleStyle(.switch)

            Toggle("Show Message Provenance (debug)", isOn: $settings.showMessageProvenance)
                .toggleStyle(.switch)

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
