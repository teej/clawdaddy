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
        "I need yer microphone to hear ya, captain!",
        "Can't listen without the mic, matey!",
        "Grant me mic access so I can catch yer orders!",
        "A lobster without a mic is just a rock on the seabed.",
    ]

    private static let speechLines = [
        "Now I need speech recognition to understand ya!",
        "One more thing — let me understand yer words, cap'n!",
        "Grant speech access so I can parse yer commands!",
        "Almost there — I need to decode yer voice!",
    ]

    private static let accessibilityLines = [
        "I need accessibility access to catch that key, matey!",
        "That key requires accessibility permissions, cap'n!",
        "Can't grab that hotkey without accessibility access!",
        "Grant accessibility so I can hear yer keystrokes!",
    ]

    private static let grantedLines = [
        "All hands on deck! Ready to serve, cap'n!",
        "Aye aye! All systems go!",
        "Anchors aweigh! I'm all ears now!",
        "Full speed ahead — permissions locked in!",
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
