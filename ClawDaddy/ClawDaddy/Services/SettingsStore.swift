import Foundation

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var pttKey: PTTKey {
        didSet { save() }
    }
    @Published var useFoundationModels: Bool {
        didSet { saveFoundationModelsToggle() }
    }
    @Published var showMessageProvenance: Bool {
        didSet { saveShowMessageProvenanceToggle() }
    }

    private let key = "clawdaddy.pttKey"
    private let foundationModelsKey = "clawdaddy.useFoundationModels"
    private let showMessageProvenanceKey = "clawdaddy.showMessageProvenance"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(PTTKey.self, from: data) {
            pttKey = decoded
        } else {
            pttKey = .defaultKey
        }
        if UserDefaults.standard.object(forKey: foundationModelsKey) == nil {
            useFoundationModels = true
        } else {
            useFoundationModels = UserDefaults.standard.bool(forKey: foundationModelsKey)
        }
        if UserDefaults.standard.object(forKey: showMessageProvenanceKey) == nil {
            showMessageProvenance = true
        } else {
            showMessageProvenance = UserDefaults.standard.bool(forKey: showMessageProvenanceKey)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pttKey) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func resetToDefault() {
        pttKey = .defaultKey
        useFoundationModels = true
        showMessageProvenance = true
    }

    private func saveFoundationModelsToggle() {
        UserDefaults.standard.set(useFoundationModels, forKey: foundationModelsKey)
    }

    private func saveShowMessageProvenanceToggle() {
        UserDefaults.standard.set(showMessageProvenance, forKey: showMessageProvenanceKey)
    }
}
