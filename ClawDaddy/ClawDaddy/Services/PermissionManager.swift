import AVFoundation
import Cocoa
import Speech

// MARK: - Permission Status

enum PermissionStatus: Equatable {
    case notDetermined
    case granted
    case denied
    case restricted
}

// MARK: - In-Character Lines

enum PermissionLines {
    enum Category {
        case mic
        case speech
        case accessibility
        case granted
    }

    static func randomLine(for category: Category) -> String {
        switch category {
        case .mic:
            return micLines.randomElement()!
        case .speech:
            return speechLines.randomElement()!
        case .accessibility:
            return accessibilityLines.randomElement()!
        case .granted:
            return grantedLines.randomElement()!
        }
    }

    private static let micLines = [
        "I need the mic, Captain.",
        "No mic, no orders. Flip that switch, Captain.",
        "Grant microphone access so I can hear your command.",
        "Open the mic hatch and I'm listening.",
        "Give me mic access and these claws are on duty.",
        "I hear the surf, not your voice. Mic access, please.",
        "One quick permission and I'll catch every order.",
        "Quick check: microphone access required.",
    ]

    private static let speechLines = [
        "Now I need speech recognition.",
        "One more hatch, Captain: speech access.",
        "Grant speech access so I can parse your orders.",
        "Mic is live. Now let me understand your words.",
        "Give me speech permission and I'll decode every command.",
        "Almost shipshape. Speech recognition is the last step.",
        "Let me translate your orders into action, Captain.",
        "Final switch: speech recognition, then we sail.",
    ]

    private static let accessibilityLines = [
        "I need accessibility access to catch that hotkey, Captain.",
        "That keybind is behind accessibility permissions.",
        "I can't grab the key without that access.",
        "Grant accessibility and I'll catch each key press.",
        "Open accessibility and these claws can watch the keyboard.",
        "Hotkey duty needs accessibility permission.",
        "Give me accessibility access and I'll take keyboard watch.",
        "Accessibility granted means the keybind is mine.",
    ]

    private static let grantedLines = [
        "Aye aye, Captain. Ready to serve.",
        "Permissions locked in. Claws on deck.",
        "All green, Captain. Ready for your orders.",
        "Bridge secured. Standing by.",
        "We're shipshape and listening, Captain.",
        "Systems are clear. Let's set a course.",
        "Anchors up. I'm ready to hear you now.",
        "Deck is clear and I'm on watch.",
    ]
}

// MARK: - PermissionManager

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var micStatus: PermissionStatus = .notDetermined
    @Published private(set) var speechStatus: PermissionStatus = .notDetermined
    @Published private(set) var accessibilityGranted = false

    private var monitoringTask: Task<Void, Never>?

    var canRecord: Bool {
        micStatus == .granted && speechStatus == .granted
    }

    func needsAccessibility(for key: PTTKey) -> Bool {
        !key.isModifier && !AXIsProcessTrusted()
    }

    // MARK: - Requests

    func requestMicPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        micStatus = granted ? .granted : .denied
    }

    func requestSpeechPermission() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        speechStatus = mapSpeechStatus(status)
    }

    // MARK: - Settings Deep Links

    func openMicSettings() {
        openSystemPreferences("com.apple.preference.security?Privacy_Microphone")
    }

    func openSpeechSettings() {
        openSystemPreferences("com.apple.preference.security?Privacy_SpeechRecognition")
    }

    func openAccessibilitySettings() {
        openSystemPreferences("com.apple.preference.security?Privacy_Accessibility")
    }

    private func openSystemPreferences(_ path: String) {
        if let url = URL(string: "x-apple.systempreferences:\(path)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        refreshStatuses()
        monitoringTask?.cancel()
        monitoringTask = Task {
            var accessibilityTick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s base
                guard !Task.isCancelled else { break }

                // Accessibility: every 2s
                let trusted = AXIsProcessTrusted()
                if trusted != accessibilityGranted {
                    accessibilityGranted = trusted
                }

                // Mic + speech revocation: every ~6s (3 ticks)
                accessibilityTick += 1
                if accessibilityTick >= 3 {
                    accessibilityTick = 0
                    refreshStatuses()
                }
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // MARK: - Private

    private func refreshStatuses() {
        micStatus = mapMicStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        speechStatus = mapSpeechStatus(SFSpeechRecognizer.authorizationStatus())
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func mapMicStatus(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    private func mapSpeechStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }
}
