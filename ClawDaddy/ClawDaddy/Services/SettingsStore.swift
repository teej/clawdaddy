import Foundation

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var pttKey: PTTKey {
        didSet { save() }
    }
    @Published var useFoundationModels: Bool {
        didSet { saveFoundationModelsToggle() }
    }

    private let key = "clawdaddy.pttKey"
    private let foundationModelsKey = "clawdaddy.useFoundationModels"

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
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pttKey) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func resetToDefault() {
        pttKey = .defaultKey
        useFoundationModels = true
    }

    private func saveFoundationModelsToggle() {
        UserDefaults.standard.set(useFoundationModels, forKey: foundationModelsKey)
    }
}
