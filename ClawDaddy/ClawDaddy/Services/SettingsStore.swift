import Foundation

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var pttKey: PTTKey {
        didSet { save() }
    }

    private let key = "clawdaddy.pttKey"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(PTTKey.self, from: data) {
            pttKey = decoded
        } else {
            pttKey = .defaultKey
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pttKey) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func resetToDefault() {
        pttKey = .defaultKey
    }
}
