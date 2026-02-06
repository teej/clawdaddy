import CryptoKit
import Darwin
import Foundation
import os
import SwiftUI

private let logger = Logger(subsystem: "com.teej.ClawDaddy", category: "WebSocket")

private struct OpenClawDiscovery {
    var wsURL: URL?
    var apiKey: String?
    var authMode: String
}

private struct DeviceIdentity {
    var deviceID: String
    var publicKeyBase64URL: String
    var privateKeySeed: Data
}

final class WebSocketClient: ObservableObject {
    @Published var appState = AppState.empty

    private var task: URLSessionWebSocketTask?
    private var isConnecting = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var pingTimer: Timer?
    private var idleWorkItem: DispatchWorkItem?
    private var thinkingFlavorWorkItem: DispatchWorkItem?
    private var observationWorkItem: DispatchWorkItem?
    private var pending: [String: (Bool, Any?, String?) -> Void] = [:]
    private var sessionKey: String?
    private var currentResponse = ""
    private var lastChatAt: Date?
    private var pendingMessages: [(text: String, subAgentId: String?)] = []
    private var cleanupWorkItems: [String: DispatchWorkItem] = [:]
    private var challengePayload: [String: Any]?
    private var challengeWaitWorkItem: DispatchWorkItem?
    private var didSendConnectRequest = false
    private var deviceIdentity: DeviceIdentity?

    private var wsURL: URL?
    private var authMode = "token"
    private var apiKey: String?
    private var chatMethod = "chat.send"
    private var idleDelay = 1.5
    private var subAgentCleanupDelay = 8.0
    private var reunionThreshold = 1800.0
    private var protocolMin = 3
    private var protocolMax = 3
    private var clientVersion = "0.1.0"
    private var clientID = "gateway-client"
    private var clientMode = "backend"
    private var clientInstanceID = "clawdaddy-mac"
    private var sessionAgentsCompleted = 0
    private var configDiagnostics = "config diagnostics unavailable"
    private var identityDiagnostics = "identity diagnostics unavailable"
    private var openclawExecutable: String?

    private var isOpen: Bool {
        task?.state == .running
    }

    func connect() {
        guard !isConnecting, !isOpen else { return }
        isConnecting = true
        refreshConfig()
        guard let wsURL else {
            logger.error("OpenClaw gateway discovery failed. \(self.configDiagnostics, privacy: .public)")
            setDisconnectedMessage("OpenClaw gateway not configured. See Console logs for details.")
            isConnecting = false
            return
        }
        guard deviceIdentity != nil else {
            logger.error("OpenClaw device identity load failed. \(self.identityDiagnostics, privacy: .public)")
            setDisconnectedMessage("OpenClaw device identity not found. See Console logs for details.")
            isConnecting = false
            return
        }

        task = URLSession.shared.webSocketTask(with: wsURL)
        task?.resume()
        receive()
        startPingTimer()
        challengePayload = nil
        didSendConnectRequest = false
        challengeWaitWorkItem?.cancel()
        let wait = DispatchWorkItem { [weak self] in
            self?.sendConnectRequestIfNeeded()
        }
        challengeWaitWorkItem = wait
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: wait)
    }

    func disconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        stopPingTimer()
        idleWorkItem?.cancel()
        idleWorkItem = nil
        stopThinkingFlavor()
        observationWorkItem?.cancel()
        observationWorkItem = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnecting = false
        sessionKey = nil
        pending.removeAll()
        challengeWaitWorkItem?.cancel()
        challengeWaitWorkItem = nil
        didSendConnectRequest = false
        sessionAgentsCompleted = 0
    }

    func sendTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let isReunion = checkReunion()
        updateClawDaddy(state: "speaking", lastResponse: pickAckLine(text: trimmed, isReunion: isReunion), isGreeting: false, isReunion: isReunion)
        updateClawDaddy(state: "thinking")
        startThinkingFlavor()
        pendingMessages.append((trimmed, nil))
        connect()
        flushPendingMessages()
    }

    func sendInputResponse(_ text: String, subAgentId: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let subAgentId {
            updateSubAgent(
                id: subAgentId,
                state: "working",
                taskDescription: "OpenClaw task",
                question: nil,
                result: nil,
                error: nil
            )
        }
        updateClawDaddy(state: "thinking")
        startThinkingFlavor()
        pendingMessages.append((trimmed, subAgentId))
        connect()
        flushPendingMessages()
    }

    private func refreshConfig() {
        let discovered = discoverOpenClawConfig()
        wsURL = discovered.wsURL
        apiKey = discovered.apiKey
        authMode = discovered.authMode
        protocolMin = Int(ProcessInfo.processInfo.environment["OPENCLAW_PROTOCOL_MIN"] ?? "3") ?? 3
        protocolMax = Int(ProcessInfo.processInfo.environment["OPENCLAW_PROTOCOL_MAX"] ?? "3") ?? 3
        clientVersion = ProcessInfo.processInfo.environment["OPENCLAW_CLIENT_VERSION"] ?? "0.1.0"
        clientID = "gateway-client"
        clientMode = "backend"
        clientInstanceID = ProcessInfo.processInfo.environment["OPENCLAW_CLIENT_INSTANCE_ID"] ??
            "clawdaddy-\(Host.current().localizedName ?? "mac")"
        chatMethod = ProcessInfo.processInfo.environment["OPENCLAW_CHAT_METHOD"] ?? "chat.send"
        idleDelay = Double(ProcessInfo.processInfo.environment["OPENCLAW_IDLE_DELAY"] ?? "1.5") ?? 1.5
        subAgentCleanupDelay = Double(ProcessInfo.processInfo.environment["OPENCLAW_SUBAGENT_CLEANUP_DELAY"] ?? "8") ?? 8
        reunionThreshold = Double(ProcessInfo.processInfo.environment["OPENCLAW_REUNION_THRESHOLD"] ?? "1800") ?? 1800
        openclawExecutable = resolveOpenClawExecutable()
        let identityResult = loadDeviceIdentityWithDiagnostics()
        deviceIdentity = identityResult.identity
        identityDiagnostics = identityResult.diagnostics
        logger.info("OpenClaw discovery summary: \(self.configDiagnostics, privacy: .public)")
        logger.info("OpenClaw identity summary: \(self.identityDiagnostics, privacy: .public)")
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
            handleText(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handleText(text)
            }
        @unknown default:
            break
        }
    }

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let envelope = json as? [String: Any],
              let type = envelope["type"] as? String else {
            return
        }
        switch type {
        case "res":
            handleResponse(envelope)
        case "event":
            handleEvent(name: envelope["event"] as? String, payload: envelope["payload"])
        default:
            break
        }
    }

    private func startPingTimer() {
        stopPingTimer()
        DispatchQueue.main.async {
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                self?.sendPing()
            }
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func sendPing() {
        task?.sendPing { [weak self] error in
            if error != nil {
                self?.scheduleReconnect()
            }
        }
    }

    private func sendConnectRequestIfNeeded() {
        guard !didSendConnectRequest else { return }
        didSendConnectRequest = true
        var params: [String: Any] = [
            "minProtocol": protocolMin,
            "maxProtocol": protocolMax,
            "client": [
                "id": clientID,
                "instanceId": clientInstanceID,
                "version": clientVersion,
                "platform": "darwin",
                "mode": clientMode,
            ],
            "caps": [],
            "role": "operator",
            "scopes": ["operator.admin"],
            "locale": "en-US",
            "userAgent": "openclaw-cli/\(clientVersion)",
        ]
        if deviceIdentity != nil {
            guard let deviceParams = buildDeviceParams(challenge: challengePayload) else {
                isConnecting = false
                sessionKey = nil
                setDisconnectedMessage("OpenClaw device auth failed. Re-run `openclaw onboard`.")
                scheduleReconnect()
                return
            }
            params["device"] = deviceParams
        }
        if let apiKey, !apiKey.isEmpty {
            if authMode == "password" {
                params["auth"] = ["password": apiKey]
            } else {
                params["auth"] = ["token": apiKey]
            }
        }
        sendRequest(method: "connect", params: params) { [weak self] ok, payload, error in
            guard let self else { return }
            self.isConnecting = false
            if ok, let payload {
                self.sessionKey = self.extractSessionKey(payload: payload)
                self.updateClawDaddy(
                    state: "speaking",
                    lastResponse: self.connectedMessage(),
                    isGreeting: true,
                    isReunion: false
                )
                self.scheduleIdle()
                self.startObservationLoop()
                self.flushPendingMessages()
                return
            }
            self.sessionKey = nil
            self.setDisconnectedMessage("OpenClaw connect failed: \(error ?? "unknown error")")
            self.scheduleReconnect()
        }
    }

    private func sendRequest(
        method: String,
        params: [String: Any],
        completion: ((Bool, Any?, String?) -> Void)? = nil
    ) {
        let requestID = UUID().uuidString
        if let completion {
            pending[requestID] = completion
        }
        let message: [String: Any] = [
            "type": "req",
            "id": requestID,
            "method": method,
            "params": params,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let payload = String(data: data, encoding: .utf8) else {
            pending.removeValue(forKey: requestID)
            return
        }
        task?.send(.string(payload)) { [weak self] error in
            if error != nil {
                self?.pending.removeValue(forKey: requestID)
                self?.scheduleReconnect()
            }
        }
    }

    private func flushPendingMessages() {
        guard isOpen, let sessionKey else { return }
        guard !pendingMessages.isEmpty else { return }
        let queued = pendingMessages
        pendingMessages.removeAll()
        for item in queued {
            currentResponse = ""
            updateClawDaddy(state: "thinking")
            startThinkingFlavor()
            let params: [String: Any] = [
                "idempotencyKey": UUID().uuidString,
                "sessionKey": sessionKey,
                "message": item.text,
            ]
            sendRequest(method: chatMethod, params: params)
        }
    }

    private func handleResponse(_ data: [String: Any]) {
        guard let requestID = data["id"] as? String else { return }
        guard let callback = pending.removeValue(forKey: requestID) else { return }
        let ok = (data["ok"] as? Bool) ?? false
        if ok {
            callback(true, data["payload"], nil)
        } else {
            let error = String(describing: data["error"] ?? "OpenClaw error")
            callback(false, nil, error)
        }
    }

    private func handleEvent(name: String?, payload: Any?) {
        if name == "connect.challenge", let payload = payload as? [String: Any] {
            challengePayload = payload
            challengeWaitWorkItem?.cancel()
            challengeWaitWorkItem = nil
            sendConnectRequestIfNeeded()
            return
        }
        switch name {
        case "chat":
            handleChatEvent(payload)
        case "agent":
            handleAgentEvent(payload)
        default:
            break
        }
    }

    private func handleChatEvent(_ payload: Any?) {
        stopThinkingFlavor()
        let role = extractRole(payload)
        if role == "user" {
            return
        }
        let text = extractText(payload)
        guard !text.isEmpty else { return }
        if isDelta(payload) {
            currentResponse += text
        } else {
            currentResponse = text
        }
        updateClawDaddy(
            state: "speaking",
            lastResponse: currentResponse,
            isGreeting: false,
            isReunion: false
        )
        scheduleIdle()
    }

    private func handleAgentEvent(_ payload: Any?) {
        guard let payload = payload as? [String: Any] else { return }
        guard let rawID = payload["id"] ?? payload["agentId"] ?? payload["agent_id"] else { return }
        let agentID = String(describing: rawID)
        let rawState = String(describing: payload["state"] ?? payload["status"] ?? "").lowercased()
        let normalizedState = normalizeAgentState(rawState)
        let taskDescription = String(describing: payload["task"] ?? payload["description"] ?? "OpenClaw task")
        let question = payload["question"] as? String
        let result = payload["result"] as? String ?? payload["output"] as? String
        let error = payload["error"] as? String

        updateSubAgent(
            id: agentID,
            state: normalizedState,
            taskDescription: taskDescription,
            question: question,
            result: result,
            error: error
        )

        cleanupWorkItems[agentID]?.cancel()
        if normalizedState == "done" || normalizedState == "error" {
            if normalizedState == "done" {
                sessionAgentsCompleted += 1
            }
            let workItem = DispatchWorkItem { [weak self] in
                self?.removeSubAgent(agentID)
            }
            cleanupWorkItems[agentID] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + subAgentCleanupDelay, execute: workItem)
        }
    }

    private func setDisconnectedMessage(_ message: String) {
        updateClawDaddy(state: "speaking", lastResponse: message, isGreeting: false, isReunion: false)
    }

    private func updateClawDaddy(
        state: String,
        lastResponse: String? = nil,
        isGreeting: Bool? = nil,
        isReunion: Bool? = nil
    ) {
        DispatchQueue.main.async {
            self.appState.clawdaddy.state = state
            if let lastResponse {
                self.appState.clawdaddy.lastResponse = lastResponse
            }
            if let isGreeting {
                self.appState.clawdaddy.isGreeting = isGreeting
            }
            if let isReunion {
                self.appState.clawdaddy.isReunion = isReunion
            }
        }
    }

    private func updateSubAgent(
        id: String,
        state: String,
        taskDescription: String,
        question: String?,
        result: String?,
        error: String?
    ) {
        DispatchQueue.main.async {
            var stateModel = self.appState
            if let idx = stateModel.subAgents.firstIndex(where: { $0.id == id }) {
                stateModel.subAgents[idx].state = state
                stateModel.subAgents[idx].taskDescription = taskDescription
                stateModel.subAgents[idx].question = question
                stateModel.subAgents[idx].result = result
                stateModel.subAgents[idx].error = error
                stateModel.subAgents[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
            } else {
                stateModel.subAgents.append(
                    SubAgentState(
                        id: id,
                        state: state,
                        taskDescription: taskDescription,
                        question: question,
                        result: result,
                        error: error,
                        updatedAt: ISO8601DateFormatter().string(from: Date())
                    )
                )
            }
            self.appState = stateModel
        }
    }

    private func removeSubAgent(_ id: String) {
        DispatchQueue.main.async {
            var stateModel = self.appState
            stateModel.subAgents.removeAll(where: { $0.id == id })
            self.appState = stateModel
        }
    }

    private func scheduleIdle() {
        idleWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateClawDaddy(state: "idle")
        }
        idleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + idleDelay, execute: workItem)
    }

    private func startThinkingFlavor() {
        stopThinkingFlavor()
        let first = DispatchWorkItem { [weak self] in
            self?.runThinkingFlavorTick()
        }
        thinkingFlavorWorkItem = first
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: first)
    }

    private func stopThinkingFlavor() {
        thinkingFlavorWorkItem?.cancel()
        thinkingFlavorWorkItem = nil
    }

    private func runThinkingFlavorTick() {
        guard appState.clawdaddy.state == "thinking" else { return }
        let lines = [
            "Consulting the charts...",
            "Checking the rigging...",
            "Gathering the crew...",
            "Scouting the horizon...",
            "Charting a course...",
            "Diving deep...",
            "Reading the currents...",
            "Weighing anchor on that one...",
        ]
        updateClawDaddy(state: "thinking", lastResponse: lines.randomElement() ?? "Consulting the charts...")
        let delay = Double.random(in: 5.0...8.0)
        let next = DispatchWorkItem { [weak self] in
            self?.runThinkingFlavorTick()
        }
        thinkingFlavorWorkItem = next
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: next)
    }

    private func startObservationLoop() {
        observationWorkItem?.cancel()
        let delay = Double.random(in: 7200...9000)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.appState.clawdaddy.state == "idle" {
                let idlePool = [
                    "Calm seas today.",
                    "Quiet on deck.",
                    "The horizon looks clear.",
                    "Good weather for sailing.",
                ]
                let busyPool = [
                    "The crew's been busy.",
                    "Good haul today, cap'n.",
                    "Productive waters today.",
                    "Running a tight ship, cap'n.",
                ]
                let pool = self.sessionAgentsCompleted >= 3 ? busyPool : idlePool
                self.updateClawDaddy(
                    state: "speaking",
                    lastResponse: pool.randomElement() ?? "Calm seas today.",
                    isGreeting: false,
                    isReunion: false
                )
                self.scheduleIdle()
            }
            self.startObservationLoop()
        }
        observationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func checkReunion() -> Bool {
        let now = Date()
        defer { lastChatAt = now }
        guard let lastChatAt else { return false }
        return now.timeIntervalSince(lastChatAt) > reunionThreshold
    }

    private func connectedMessage() -> String {
        let generic = [
            "Welcome aboard.",
            "Standing by at the helm.",
            "Awaiting your command.",
            "Where shall we set course?",
            "Ready for orders, Captain.",
            "Deck's clear and ready.",
            "All systems shipshape.",
            "Set the course, Captain.",
            "At your service, Captain.",
            "What's the plan, Captain?",
        ]
        let hour = Calendar.current.component(.hour, from: Date())
        let timed: [String]
        switch hour {
        case 5..<12:
            timed = [
                "Good morning, Captain.",
                "Rise and shine, Captain.",
                "Morning watch begins.",
                "Dawn's breaking. Ready when you are.",
            ]
        case 12..<17:
            timed = [
                "Good afternoon, Captain.",
                "Afternoon watch, reporting in.",
                "Smooth sailing this afternoon.",
                "Sun's high. What's our heading?",
            ]
        case 17..<22:
            timed = [
                "Good evening, Captain.",
                "Evening watch, standing by.",
                "Stars are coming out, Captain.",
                "Settling in for the evening watch.",
            ]
        default:
            timed = [
                "Burning the midnight oil, Captain?",
                "Night watch, reporting in.",
                "Quiet seas tonight, Captain.",
                "Late night on deck, Captain.",
            ]
        }
        return (timed + generic).randomElement() ?? "Welcome aboard."
    }

    private func pickAckLine(text: String, isReunion: Bool) -> String {
        if isReunion {
            return ["There ye are, cap'n!", "Back on deck, cap'n!"].randomElement() ?? "There ye are, cap'n!"
        }
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        if wordCount <= 5 {
            return ["On it.", "Aye.", "Right away."].randomElement() ?? "On it."
        }
        if wordCount > 25 {
            return ["That's a tall order. Setting course.", "Long haul ahead. Charting route."].randomElement() ?? "Setting course."
        }
        return [
            "Aye aye, cap'n!",
            "On it, skipper.",
            "Charting it now.",
            "All hands on it.",
            "Claws to work.",
        ].randomElement() ?? "On it, skipper."
    }

    private func normalizeAgentState(_ rawState: String) -> String {
        if ["waiting", "needs_input", "input", "waiting_for_input"].contains(rawState) {
            return "waiting_for_input"
        }
        if ["done", "complete", "completed", "finished", "success"].contains(rawState) {
            return "done"
        }
        if ["error", "failed", "failure"].contains(rawState) {
            return "error"
        }
        return "working"
    }

    private func extractSessionKey(payload: Any) -> String? {
        guard let payload = payload as? [String: Any] else { return nil }
        if let direct = payload["sessionKey"] as? String, !direct.isEmpty {
            return direct
        }
        guard let snapshot = payload["snapshot"] as? [String: Any],
              let defaults = snapshot["sessionDefaults"] as? [String: Any],
              let key = defaults["mainSessionKey"] as? String,
              !key.isEmpty else {
            return nil
        }
        return key
    }

    private func extractRole(_ payload: Any?) -> String? {
        guard let payload = payload as? [String: Any] else { return nil }
        if let role = payload["role"] as? String {
            return role
        }
        if let message = payload["message"] as? [String: Any], let role = message["role"] as? String {
            return role
        }
        return nil
    }

    private func extractText(_ payload: Any?) -> String {
        if let text = payload as? String {
            return text
        }
        if let payload = payload as? [String: Any] {
            for key in ["text", "message", "content", "delta", "result", "output"] {
                if let value = payload[key] {
                    let text = extractText(value)
                    if !text.isEmpty {
                        return text
                    }
                }
            }
        }
        if let payload = payload as? [[String: Any]] {
            var parts: [String] = []
            for item in payload {
                if let type = item["type"] as? String, type == "text", let text = item["text"] as? String {
                    parts.append(text)
                }
            }
            return parts.joined()
        }
        if let payload = payload as? [String] {
            return payload.joined()
        }
        return ""
    }

    private func isDelta(_ payload: Any?) -> Bool {
        guard let payload = payload as? [String: Any] else { return false }
        if let type = payload["type"] as? String, type == "delta" || type == "partial" {
            return true
        }
        return payload["delta"] != nil
    }

    private func buildDeviceParams(challenge: [String: Any]?) -> [String: Any]? {
        guard let identity = deviceIdentity else { return nil }
        let signedAt = Int(Date().timeIntervalSince1970 * 1000)
        let nonce = challenge?["nonce"] as? String
        let payload = buildDeviceAuthPayload(
            deviceID: identity.deviceID,
            signedAtMS: signedAt,
            token: apiKey,
            nonce: nonce
        )
        guard let signature = signPayload(seed: identity.privateKeySeed, payload: payload) else {
            logger.error("OpenClaw device payload signing failed")
            return nil
        }
        var params: [String: Any] = [
            "id": identity.deviceID,
            "publicKey": identity.publicKeyBase64URL,
            "signature": signature,
            "signedAt": signedAt,
        ]
        if let nonce, !nonce.isEmpty {
            params["nonce"] = nonce
        }
        return params
    }

    private func buildDeviceAuthPayload(
        deviceID: String,
        signedAtMS: Int,
        token: String?,
        nonce: String?
    ) -> String {
        let version = (nonce?.isEmpty == false) ? "v2" : "v1"
        let scopesJoined = "operator.admin"
        var components: [String] = [
            version,
            deviceID,
            clientID,
            clientMode,
            "operator",
            scopesJoined,
            String(signedAtMS),
            token ?? "",
        ]
        if version == "v2" {
            components.append(nonce ?? "")
        }
        return components.joined(separator: "|")
    }

    private func signPayload(seed: Data, payload: String) -> String? {
        guard let payloadData = payload.data(using: .utf8) else { return nil }
        do {
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            let signature = try key.signature(for: payloadData)
            return base64urlEncode(signature)
        } catch {
            logger.error("OpenClaw signing error: \(error.localizedDescription)")
            return nil
        }
    }

    private func loadDeviceIdentityWithDiagnostics() -> (identity: DeviceIdentity?, diagnostics: String) {
        let env = ProcessInfo.processInfo.environment
        let candidatePaths: [String]
        if let explicit = env["OPENCLAW_DEVICE_PATH"], !explicit.isEmpty {
            candidatePaths = [explicit]
        } else {
            candidatePaths = openclawStateDirs().map { "\($0)/identity/device.json" }
        }
        let path = candidatePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? (candidatePaths.first ?? "")
        var notes = [
            "path=\(path)",
            "file_exists=\(FileManager.default.fileExists(atPath: path))",
            "candidates=\(candidatePaths.joined(separator: ","))",
        ]
        let json: [String: Any]
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                notes.append("parse=device_json_invalid")
                return (nil, notes.joined(separator: " | "))
            }
            json = parsed
        } catch {
            notes.append("read_error=\(error.localizedDescription)")
            return (nil, notes.joined(separator: " | "))
        }
        guard let publicPEM = (json["publicKeyPem"] as? String) ?? (json["publicKey"] as? String) else {
            notes.append("missing=public_pem")
            return (nil, notes.joined(separator: " | "))
        }
        guard let privatePEM = json["privateKeyPem"] as? String else {
            notes.append("missing=private_pem")
            return (nil, notes.joined(separator: " | "))
        }
        guard let publicRaw = extractPublicKeyRaw(fromPEM: publicPEM) else {
            notes.append("decode=public_key_failed")
            return (nil, notes.joined(separator: " | "))
        }
        guard let privateSeed = extractPrivateSeed(fromPEM: privatePEM) else {
            notes.append("decode=private_key_failed")
            return (nil, notes.joined(separator: " | "))
        }
        let publicKeyBase64URL = base64urlEncode(publicRaw)
        let derivedDeviceID = SHA256.hash(data: publicRaw).map { String(format: "%02x", $0) }.joined()
        let fallbackDeviceID = (json["deviceId"] as? String) ?? (json["id"] as? String) ?? derivedDeviceID
        let identity = DeviceIdentity(
            deviceID: derivedDeviceID.isEmpty ? fallbackDeviceID : derivedDeviceID,
            publicKeyBase64URL: publicKeyBase64URL,
            privateKeySeed: privateSeed
        )
        notes.append("device_id=\(identity.deviceID.prefix(8))...")
        notes.append("public_key_len=\(identity.publicKeyBase64URL.count)")
        return (identity, notes.joined(separator: " | "))
    }

    private func extractPublicKeyRaw(fromPEM pem: String) -> Data? {
        guard let der = pemToDER(pem) else { return nil }
        if let bitString = derFindFirst(tag: 0x03, in: der), bitString.count >= 33, bitString[0] == 0 {
            if bitString.count == 33 {
                return Data(bitString.dropFirst())
            }
            return Data(bitString.suffix(32))
        }
        if der.count >= 32 {
            return Data(der.suffix(32))
        }
        return nil
    }

    private func extractPrivateSeed(fromPEM pem: String) -> Data? {
        guard let der = pemToDER(pem) else { return nil }
        let octets = derFindAll(tag: 0x04, in: der)
        if let direct = octets.first(where: { $0.count == 32 }) {
            return direct
        }
        for octet in octets {
            let nested = derFindAll(tag: 0x04, in: octet)
            if let seed = nested.first(where: { $0.count == 32 }) {
                return seed
            }
            if octet.count >= 32 {
                return Data(octet.suffix(32))
            }
        }
        return nil
    }

    private func pemToDER(_ pem: String) -> Data? {
        let lines = pem
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.hasPrefix("-----") }
        guard !lines.isEmpty else { return nil }
        return Data(base64Encoded: lines.joined())
    }

    private func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func derFindFirst(tag: UInt8, in data: Data) -> Data? {
        derFindAll(tag: tag, in: data).first
    }

    private func derFindAll(tag: UInt8, in data: Data) -> [Data] {
        var results: [Data] = []
        var idx = data.startIndex
        while idx < data.endIndex {
            let start = idx
            let t = data[idx]
            idx = data.index(after: idx)
            guard idx < data.endIndex else { break }
            let lengthByte = data[idx]
            idx = data.index(after: idx)

            var length = 0
            if (lengthByte & 0x80) == 0 {
                length = Int(lengthByte)
            } else {
                let count = Int(lengthByte & 0x7F)
                guard count > 0 else { break }
                guard data.distance(from: idx, to: data.endIndex) >= count else { break }
                for _ in 0..<count {
                    length = (length << 8) | Int(data[idx])
                    idx = data.index(after: idx)
                }
            }
            guard length >= 0 else { break }
            guard data.distance(from: idx, to: data.endIndex) >= length else { break }

            let valueStart = idx
            let valueEnd = data.index(valueStart, offsetBy: length)
            let value = data[valueStart..<valueEnd]
            if t == tag {
                results.append(Data(value))
            }
            // Recurse only for constructed tags.
            if (t & 0x20) == 0x20 {
                results.append(contentsOf: derFindAll(tag: tag, in: Data(value)))
            }
            idx = valueEnd
            if idx <= start { break }
        }
        return results
    }

    private func discoverOpenClawConfig() -> OpenClawDiscovery {
        let env = ProcessInfo.processInfo.environment
        var wsURL = URL(string: env["OPENCLAW_WS_URL"] ?? "")
        var apiKey = env["OPENCLAW_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        var authMode = env["OPENCLAW_AUTH_MODE"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stateDirs = openclawStateDirs()
        var source = "env"
        var notes = [
            "openclaw_bin=\(openclawExecutable ?? "nil")",
            "state_dirs=\(stateDirs.joined(separator: ","))",
            "env_ws_url=\(wsURL?.absoluteString.isEmpty == false)",
            "env_api_key=\(secretState(apiKey))",
            "env_auth_mode=\(authMode ?? "nil")",
        ]

        if wsURL == nil || apiKey == nil {
            let cli = discoverViaCLIWithDiagnostics()
            notes.append("cli=\(cli.details)")
            if let cliDiscovery = cli.discovery {
                if wsURL == nil { wsURL = cliDiscovery.wsURL }
                if apiKey == nil { apiKey = cliDiscovery.apiKey }
                if authMode == nil { authMode = cliDiscovery.authMode }
                source = "cli"
            }
        }
        if wsURL == nil || apiKey == nil {
            let file = discoverViaFileWithDiagnostics()
            notes.append("file=\(file.details)")
            if let fileDiscovery = file.discovery {
                if wsURL == nil { wsURL = fileDiscovery.wsURL }
                if apiKey == nil { apiKey = fileDiscovery.apiKey }
                if authMode == nil { authMode = fileDiscovery.authMode }
                source = "file"
            }
        }
        let result = OpenClawDiscovery(
            wsURL: wsURL,
            apiKey: apiKey,
            authMode: authMode?.isEmpty == false ? authMode! : "token"
        )
        notes.append("source=\(source)")
        notes.append("resolved_ws_url=\(result.wsURL?.absoluteString ?? "nil")")
        notes.append("resolved_api_key=\(secretState(result.apiKey))")
        notes.append("resolved_auth_mode=\(result.authMode)")
        configDiagnostics = notes.joined(separator: " | ")
        return result
    }

    private func discoverViaCLIWithDiagnostics() -> (discovery: OpenClawDiscovery?, details: String) {
        let remoteURL = cliGetDetailed("gateway.remote.url")
        let remoteToken = cliGetDetailed("gateway.remote.token")
        var notes = [
            "remote.url=\(remoteURL.detail)",
            "remote.token=\(remoteToken.detail)",
        ]
        if let remoteURLValue = remoteURL.value, !remoteURLValue.isEmpty {
            notes.append("path=remote")
            return (
                OpenClawDiscovery(wsURL: URL(string: remoteURLValue), apiKey: remoteToken.value, authMode: "token"),
                notes.joined(separator: "; ")
            )
        }
        let port = cliGetDetailed("gateway.port")
        let mode = cliGetDetailed("gateway.auth.mode")
        let token = cliGetDetailed("gateway.auth.token")
        let password = cliGetDetailed("gateway.auth.password")
        notes.append("port=\(port.detail)")
        notes.append("mode=\(mode.detail)")
        notes.append("token=\(token.detail)")
        notes.append("password=\(password.detail)")
        guard let portValue = port.value, !portValue.isEmpty else {
            notes.append("path=none")
            return (nil, notes.joined(separator: "; "))
        }
        let wsURL = URL(string: "ws://127.0.0.1:\(portValue)")
        let effectiveMode = (mode.value == "password") ? "password" : "token"
        let apiKey = effectiveMode == "password" ? password.value : token.value
        notes.append("path=local")
        return (
            OpenClawDiscovery(wsURL: wsURL, apiKey: apiKey, authMode: effectiveMode),
            notes.joined(separator: "; ")
        )
    }

    private func discoverViaFileWithDiagnostics() -> (discovery: OpenClawDiscovery?, details: String) {
        let env = ProcessInfo.processInfo.environment
        let candidatePaths: [String]
        if let explicit = env["OPENCLAW_CONFIG_PATH"], !explicit.isEmpty {
            candidatePaths = [explicit]
        } else {
            candidatePaths = openclawStateDirs().map { "\($0)/openclaw.json" }
        }
        let path = candidatePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? (candidatePaths.first ?? "")
        var notes = [
            "path=\(path)",
            "file_exists=\(FileManager.default.fileExists(atPath: path))",
            "candidates=\(candidatePaths.joined(separator: ","))",
        ]
        let gateway: [String: Any]
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parsedGateway = json["gateway"] as? [String: Any] else {
                notes.append("parse=openclaw_json_invalid")
                return (nil, notes.joined(separator: "; "))
            }
            gateway = parsedGateway
        } catch {
            notes.append("read_error=\(error.localizedDescription)")
            return (nil, notes.joined(separator: "; "))
        }

        if let remote = gateway["remote"] as? [String: Any],
           let remoteURL = remote["url"] as? String,
           !remoteURL.isEmpty {
            let remoteToken = remote["token"] as? String
            notes.append("path=remote")
            return (
                OpenClawDiscovery(wsURL: URL(string: remoteURL), apiKey: remoteToken, authMode: "token"),
                notes.joined(separator: "; ")
            )
        }

        guard let port = gateway["port"] else {
            notes.append("missing=port")
            return (nil, notes.joined(separator: "; "))
        }
        let auth = gateway["auth"] as? [String: Any] ?? [:]
        let mode = (auth["mode"] as? String) == "password" ? "password" : "token"
        let key = mode == "password" ? auth["password"] as? String : auth["token"] as? String
        notes.append("path=local")
        notes.append("auth_mode=\(mode)")
        notes.append("api_key=\(secretState(key))")
        return (
            OpenClawDiscovery(
                wsURL: URL(string: "ws://127.0.0.1:\(port)"),
                apiKey: key,
                authMode: mode
            ),
            notes.joined(separator: "; ")
        )
    }

    private func cliGetDetailed(_ path: String) -> (value: String?, detail: String) {
        guard let openclawExecutable else {
            return (nil, "openclaw_bin_unresolved")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: openclawExecutable)
        process.arguments = ["config", "get", path, "--json"]
        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput
        do {
            try process.run()
            process.waitUntilExit()
            let stderr = String(data: errorOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus == 0 else {
                return (nil, "status=\(process.terminationStatus) err=\(stderr.isEmpty ? "none" : stderr)")
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
                return (nil, "status=0 raw_decode_failed")
            }
            guard !raw.isEmpty else { return (nil, "status=0 empty") }
            if raw == "null" {
                return (nil, "status=0 null")
            }
            if raw.first == "\"", raw.last == "\"",
               let decoded = try? JSONDecoder().decode(String.self, from: Data(raw.utf8)) {
                return (decoded, "status=0 value=string")
            }
            return (raw, "status=0 value=raw")
        } catch {
            let message = "run_error=\(error.localizedDescription)"
            logger.debug("openclaw CLI lookup failed for \(path, privacy: .public): \(message, privacy: .public)")
            return (nil, message)
        }
    }

    private func resolveOpenClawExecutable() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["OPENCLAW_BIN"], !explicit.isEmpty, FileManager.default.isExecutableFile(atPath: explicit) {
            return explicit
        }

        var candidates = [
            "/opt/homebrew/bin/openclaw",
            "/usr/local/bin/openclaw",
            "/usr/bin/openclaw",
            "/bin/openclaw",
        ]
        if let path = env["PATH"], !path.isEmpty {
            for entry in path.split(separator: ":") {
                candidates.append("\(entry)/openclaw")
            }
        }

        var debugEntries: [String] = []
        for candidate in candidates {
            let exists = FileManager.default.fileExists(atPath: candidate)
            let executable = FileManager.default.isExecutableFile(atPath: candidate)
            debugEntries.append("\(candidate){exists=\(exists),exec=\(executable)}")
            if executable {
                logger.info("OpenClaw executable resolved: \(candidate, privacy: .public)")
                return candidate
            }
        }
        logger.error("OpenClaw executable unresolved; candidates=\(debugEntries.joined(separator: " | "), privacy: .public)")
        return nil
    }

    private func openclawStateDirs() -> [String] {
        let env = ProcessInfo.processInfo.environment
        var dirs: [String] = []
        if let explicit = env["OPENCLAW_STATE_DIR"], !explicit.isEmpty {
            dirs.append(explicit)
        }
        dirs.append("\(NSHomeDirectory())/.openclaw")
        if let hostHome = NSHomeDirectoryForUser(NSUserName()), !hostHome.isEmpty {
            dirs.append("\(hostHome)/.openclaw")
        }
        if let pwHome = passwdHome(), !pwHome.isEmpty {
            dirs.append("\(pwHome)/.openclaw")
        }
        var seen: Set<String> = []
        return dirs.filter { seen.insert($0).inserted }
    }

    private func passwdHome() -> String? {
        guard let pw = getpwuid(getuid()) else { return nil }
        guard let dir = pw.pointee.pw_dir else { return nil }
        return String(cString: dir)
    }

    private func secretState(_ value: String?) -> String {
        guard let value else { return "nil" }
        if value.isEmpty { return "empty" }
        return "set(len=\(value.count))"
    }

    private func scheduleReconnect() {
        stopPingTimer()
        idleWorkItem?.cancel()
        idleWorkItem = nil
        stopThinkingFlavor()
        observationWorkItem?.cancel()
        observationWorkItem = nil
        challengeWaitWorkItem?.cancel()
        challengeWaitWorkItem = nil
        challengePayload = nil
        if reconnectWorkItem != nil {
            return
        }
        isConnecting = false
        sessionKey = nil
        didSendConnectRequest = false
        task = nil
        reconnectWorkItem = DispatchWorkItem { [weak self] in
            self?.reconnectWorkItem = nil
            self?.connect()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: reconnectWorkItem!)
    }
}
