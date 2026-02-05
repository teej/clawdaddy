import Foundation
import SwiftUI

struct ClawDaddyState: Codable {
    var state: String
    var lastResponse: String

    enum CodingKeys: String, CodingKey {
        case state
        case lastResponse = "last_response"
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

struct ServerMessage: Codable {
    var type: String
    var state: AppState?
}

struct ClientMessage: Codable {
    var type: String
    var text: String
    var subAgentId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case subAgentId = "sub_agent_id"
    }
}

final class WebSocketClient: ObservableObject {
    @Published var appState = AppState.empty

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var task: URLSessionWebSocketTask?
    private var isConnected = false
    private var reconnectWorkItem: DispatchWorkItem?

    private let url = URL(string: "ws://127.0.0.1:8000/ws")!

    func connect() {
        guard !isConnected else { return }
        isConnected = true

        task = URLSession.shared.webSocketTask(with: url)
        task?.resume()
        receive()
    }

    func disconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    func sendTranscript(_ text: String) {
        send(ClientMessage(type: "transcript", text: text, subAgentId: nil))
    }

    func sendInputResponse(_ text: String, subAgentId: String?) {
        send(ClientMessage(type: "input_response", text: text, subAgentId: subAgentId))
    }

    private func send(_ message: ClientMessage) {
        guard let data = try? encoder.encode(message),
              let payload = String(data: data, encoding: .utf8) else {
            return
        }
        task?.send(.string(payload)) { [weak self] error in
            if error != nil {
                self?.scheduleReconnect()
            }
        }
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.scheduleReconnect()
            case .success(let message):
                self.handle(message)
                self.receive()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handle(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handle(text)
            }
        @unknown default:
            break
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        guard let message = try? decoder.decode(ServerMessage.self, from: data) else { return }
        if message.type == "state", let state = message.state {
            DispatchQueue.main.async {
                self.appState = state
            }
        }
    }

    private func scheduleReconnect() {
        if reconnectWorkItem != nil {
            return
        }
        isConnected = false
        reconnectWorkItem = DispatchWorkItem { [weak self] in
            self?.reconnectWorkItem = nil
            self?.connect()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: reconnectWorkItem!)
    }
}
