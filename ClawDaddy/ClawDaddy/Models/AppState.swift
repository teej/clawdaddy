import Foundation

struct ClawDaddyState: Codable {
    var state: String
    var lastResponse: String
    var isGreeting: Bool
    var isReunion: Bool

    enum CodingKeys: String, CodingKey {
        case state
        case lastResponse = "last_response"
        case isGreeting = "is_greeting"
        case isReunion = "is_reunion"
    }

    init(state: String, lastResponse: String, isGreeting: Bool = false, isReunion: Bool = false) {
        self.state = state
        self.lastResponse = lastResponse
        self.isGreeting = isGreeting
        self.isReunion = isReunion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(String.self, forKey: .state)
        lastResponse = try container.decode(String.self, forKey: .lastResponse)
        isGreeting = try container.decodeIfPresent(Bool.self, forKey: .isGreeting) ?? false
        isReunion = try container.decodeIfPresent(Bool.self, forKey: .isReunion) ?? false
    }

    static let empty = ClawDaddyState(state: "idle", lastResponse: "")
}

struct SubAgentState: Codable, Identifiable {
    var id: String
    var state: String
    var taskDescription: String
    var question: String?
    var result: String?
    var error: String?
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case state
        case taskDescription = "task_description"
        case question
        case result
        case error
        case updatedAt = "updated_at"
    }

    static let empty = SubAgentState(
        id: "empty",
        state: "working",
        taskDescription: "",
        question: nil,
        result: nil,
        error: nil,
        updatedAt: ""
    )
}

struct AppState: Codable {
    var clawdaddy: ClawDaddyState
    var subAgents: [SubAgentState]

    enum CodingKeys: String, CodingKey {
        case clawdaddy
        case subAgents = "sub_agents"
    }

    static let empty = AppState(clawdaddy: .empty, subAgents: [])
}
