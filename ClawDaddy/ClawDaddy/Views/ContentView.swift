import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var socket = WebSocketClient()
    @StateObject private var speech = SpeechManager()
    @StateObject private var settings = SettingsStore.shared

    @State private var inputText = ""
    @State private var showingInput = false
    @State private var pendingInputAgentId: String?
    @State private var wasRecording = false
    @State private var daddyModel = DaddyAnimationModel()
    @State private var bubbles: [BubbleItem] = []
    @State private var lastClawDaddyMessage = ""
    @State private var currentClawDaddyBubbleId: String?
    @State private var lastAgentMessages: [String: String] = [:]
    @State private var lastAgentStates: [String: String] = [:]
    @State private var lastTranscriptLength = 0
    @State private var thinkingHoldUntil: Date?
    @State private var bottomRowHeight: CGFloat = 0
    @State private var windowSize = CGSize(width: 320, height: 220)
    @State private var localKeyMonitor: Any?
    @State private var globalKeyMonitor: Any?
    @State private var proximityMonitor: Any?
    @State private var lastProximityReaction = Date.distantPast
    @State private var lastWindowDragReaction = Date.distantPast
    @State private var sleepTask: Task<Void, Never>?
    @State private var isSleeping = false
    @State private var lastInteractionDate = Date()
    @State private var milestones = MilestoneTracker(
        commandCount: UserDefaults.standard.integer(forKey: "clawdaddy.commandCount"),
        streakDays: 0
    )
    @State private var lastColorScheme: ColorScheme?
    @State private var isTypewriterRevealing = false
    @State private var lastSentAnimState: DaddyAnimState = .idle
    @Environment(\.colorScheme) private var colorScheme

    private let maxBubbles = 4
    private let toastInsets = EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 44)
    private let bottomRowPadding = EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 24)
    private let bubbleSpacing: CGFloat = 10
    private let showDebugBorders = false

    private var isLayoutSelfTest: Bool {
        ProcessInfo.processInfo.environment["CLAWDADDY_LAYOUT_SELFTEST"] == "1"
    }
    private var isSubAgentSelfTest: Bool {
        ProcessInfo.processInfo.environment["CLAWDADDY_SUBAGENT_SELFTEST"] == "1"
    }
    private var isUITest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            toastLayer

            bottomRow
        }
        .frame(width: windowSize.width, height: windowSize.height, alignment: .bottomTrailing)
        .debugBorder(showDebugBorders, color: .black)
        .background(WindowConfigurator(windowSize: $windowSize, isInteractive: hasInteractiveBubble))
        .onAppear {
            if isLayoutSelfTest {
                seedBubblesForLayoutTest()
            } else if isSubAgentSelfTest {
                seedSubAgentsForSelfTest()
            } else if !isUITest {
                speech.requestAuthorization()
                socket.connect()
                startKeyMonitor()
                handleMilestone(milestones.updateStreak(), delay: 3.0)
                resetSleepTimer()
                lastColorScheme = colorScheme
            }
        }
        .onDisappear {
            stopAllMonitors()
            sleepTask?.cancel()
        }
        .sheet(isPresented: $showingInput) {
            InputSheet(
                inputText: $inputText,
                onSubmit: submitInput,
                onCancel: { showingInput = false }
            )
        }
        .onChange(of: speech.isRecording) { newValue in
            if !wasRecording, newValue {
                lastTranscriptLength = 0
                resetSleepTimer()
            }
            if wasRecording, !newValue {
                lastInteractionDate = Date()
                let style: AckStyle = (lastTranscriptLength > 0 && lastTranscriptLength <= 36) ? .big : .standard
                daddyModel.send(.acknowledge(style))
                handleMilestone(milestones.trackCommand(), delay: 1.5)
            }
            wasRecording = newValue
            syncAnimState()
        }
        .onChange(of: socket.appState.clawdaddy.lastResponse) { newValue in
            guard !isLayoutSelfTest, !isSubAgentSelfTest else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != lastClawDaddyMessage else { return }
            upsertClawDaddyBubble(text: trimmed)
            if socket.appState.clawdaddy.isReunion {
                daddyModel.send(.emote(.surprised))
                daddyModel.send(.dance)
            } else if socket.appState.clawdaddy.isGreeting {
                daddyModel.send(.salute)
                daddyModel.send(.dance)
            }
        }
        .onChange(of: socket.appState.clawdaddy.state) { _, newValue in
            guard !isLayoutSelfTest, !isSubAgentSelfTest else { return }
            if newValue == "thinking" {
                setThinkingHold(duration: 2.0)
            }
            syncAnimState()
        }
        .onReceive(socket.$appState) { newState in
            guard !isLayoutSelfTest else { return }
            if newState.clawdaddy.lastResponse.isEmpty, newState.subAgents.isEmpty {
                withAnimation(.easeOut(duration: 0.25)) {
                    bubbles.removeAll()
                }
                lastAgentMessages.removeAll()
                lastAgentStates.removeAll()
                lastClawDaddyMessage = ""
                currentClawDaddyBubbleId = nil
            }
            updateSubAgentBubbles(newState.subAgents)
        }
        .onPreferenceChange(BottomRowHeightKey.self) { newValue in
            if abs(bottomRowHeight - newValue) > 0.5 {
                bottomRowHeight = newValue
            }
        }
        .onChange(of: colorScheme) { _, newScheme in
            guard let last = lastColorScheme, last != newScheme else {
                lastColorScheme = newScheme
                return
            }
            lastColorScheme = newScheme
            if newScheme == .dark {
                daddyModel.send(.reaction(.settle))
            } else {
                daddyModel.send(.reaction(.perk))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { _ in
            let now = Date()
            guard now.timeIntervalSince(lastWindowDragReaction) > 5 else { return }
            lastWindowDragReaction = now
            daddyModel.send(.reaction(.alert))
        }
        .onChange(of: isSleeping) { _ in syncAnimState() }
        .onChange(of: speech.isSpeaking) { _ in syncAnimState() }
        .onChange(of: isTypewriterRevealing) { newValue in
            daddyModel.send(.talkingChanged(newValue))
        }
    }

    private var effectiveClawDaddyState: DaddyAnimState {
        if speech.isRecording {
            return .listening
        }
        if let hold = thinkingHoldUntil, hold > Date() {
            return .thinking
        }
        if speech.isSpeaking {
            return .speaking
        }
        let socketState = socket.appState.clawdaddy.state
        if socketState == "idle" && isSleeping {
            return .sleeping
        }
        switch socketState {
        case "listening": return .listening
        case "thinking": return .thinking
        case "speaking": return .speaking
        case "waiting_for_input": return .waitingForInput
        case "sleeping": return .sleeping
        default: return .idle
        }
    }

    private struct BubbleItem: Identifiable {
        let id: String
        let text: String
        let isInteractive: Bool
        let agentId: String?
    }

    private func submitInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        socket.sendInputResponse(trimmed, subAgentId: pendingInputAgentId)
        inputText = ""
        pendingInputAgentId = nil
        showingInput = false
    }

    private func startPushToTalk() {
        if speech.isRecording {
            return
        }
        speech.startRecording { transcript in
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            lastTranscriptLength = trimmed.count
            if handleEmoteCommand(trimmed) {
                return
            }
            socket.sendTranscript(trimmed)
        }
    }

    private func stopPushToTalk() {
        if speech.isRecording {
            speech.stopRecording(after: 0.3)
        }
    }

    private func startKeyMonitor() {
        let eventMask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { event in
            handleKeyEvent(event)
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { event in
            handleKeyEvent(event)
        }

        let proximityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [self] _ in
            guard let window = NSApp.windows.first(where: { $0.level == .floating }) else { return }
            let cursor = NSEvent.mouseLocation
            let frame = window.frame
            let expanded = frame.insetBy(dx: -100, dy: -100)
            guard expanded.contains(cursor), !frame.contains(cursor) else { return }
            let now = Date()
            guard now.timeIntervalSince(lastProximityReaction) > 10 else { return }
            lastProximityReaction = now
            daddyModel.send(.reaction(.perk))
        }
        proximityMonitor = proximityTimer
    }

    private func stopAllMonitors() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let timer = proximityMonitor as? Timer {
            timer.invalidate()
        }
        proximityMonitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let pttKey = settings.pttKey
        guard event.keyCode == pttKey.keyCode else { return }

        if pttKey.isModifier {
            guard event.type == .flagsChanged, let flag = pttKey.nsModifierFlag else { return }
            if event.modifierFlags.contains(flag) {
                startPushToTalk()
            } else {
                stopPushToTalk()
            }
        } else {
            if event.type == .keyDown {
                startPushToTalk()
            } else if event.type == .keyUp {
                stopPushToTalk()
            }
        }
    }

    private var visibleBubbles: [BubbleItem] {
        Array(bubbles.suffix(maxBubbles))
    }

    private var hasInteractiveBubble: Bool {
        bubbles.contains { $0.isInteractive }
    }

    private func syncAnimState() {
        let state = effectiveClawDaddyState
        guard state != lastSentAnimState else { return }
        lastSentAnimState = state
        daddyModel.send(.stateChanged(state))
    }

    private func setThinkingHold(duration: TimeInterval) {
        let target = Date().addingTimeInterval(duration)
        thinkingHoldUntil = target
        syncAnimState()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if thinkingHoldUntil == target {
                thinkingHoldUntil = nil
                syncAnimState()
            }
        }
    }

    private func handleEmoteCommand(_ text: String) -> Bool {
        let lower = text.lowercased()
        let stripped = lower.replacingOccurrences(of: "clawdaddy", with: "")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !stripped.isEmpty else { return false }

        let tokens = stripped.split(separator: " ").map { String($0) }
        let commandTokens: [String]
        if tokens.first == "emote" || tokens.first == "animate" {
            commandTokens = Array(tokens.dropFirst())
        } else if tokens.count >= 2, tokens[0] == "do", tokens[1] == "a" {
            commandTokens = Array(tokens.dropFirst(2))
        } else if tokens.first == "wink" || tokens.first == "tilt" || tokens.first == "surprised" || tokens.first == "surprise" || tokens.first == "salute" || tokens.first == "backflip" || tokens.first == "flip" || tokens.first == "plank" || tokens.first == "walk" || tokens.first == "play" || tokens.first == "dead" || tokens.first == "spin" || tokens.first == "crab" || tokens.first == "rave" || tokens.first == "dance" || tokens.first == "nod" || tokens.first == "shake" || tokens.first == "bow" {
            commandTokens = tokens
        } else {
            return false
        }

        let command = commandTokens.joined(separator: " ")
        if command.contains("wink") {
            daddyModel.send(.emote(.wink))
            return true
        }
        if command.contains("tilt") || command.contains("head tilt") {
            daddyModel.send(.emote(.tilt))
            return true
        }
        if command.contains("surprise") || command.contains("surprised") {
            daddyModel.send(.emote(.surprised))
            return true
        }
        if command.contains("salute") {
            daddyModel.send(.salute)
            return true
        }
        if command.contains("backflip") || command.contains("flip") {
            daddyModel.send(.emote(.backflip))
            return true
        }
        if command.contains("plank") || command.contains("walk") {
            daddyModel.send(.emote(.plank))
            return true
        }
        if command.contains("play dead") || command.contains("dead") {
            daddyModel.send(.emote(.playDead))
            return true
        }
        if command.contains("spin") {
            daddyModel.send(.emote(.spin))
            return true
        }
        if command.contains("crab") || command.contains("rave") {
            daddyModel.send(.emote(.crabRave))
            return true
        }
        if command.contains("dance") {
            daddyModel.send(.dance)
            return true
        }
        if command.contains("nod") {
            daddyModel.send(.emote(.nod))
            return true
        }
        if command.contains("shake") {
            daddyModel.send(.emote(.shake))
            return true
        }
        if command.contains("bow") {
            daddyModel.send(.emote(.bow))
            return true
        }

        return false
    }

    private var toastLayer: some View {
        Group {
            if !visibleBubbles.isEmpty {
                VStack(alignment: .trailing, spacing: 6) {
                    Spacer(minLength: 0)
                    ForEach(visibleBubbles) { bubble in
                        SpeechBubbleView(
                            text: bubble.text,
                            isInteractive: bubble.isInteractive,
                            typewriter: !bubble.isInteractive && bubble.agentId == nil,
                            onRevealChange: (!bubble.isInteractive && bubble.agentId == nil) ? { revealing in
                                isTypewriterRevealing = revealing
                            } : nil
                        ) {
                            if bubble.isInteractive {
                                pendingInputAgentId = bubble.agentId
                                showingInput = true
                            }
                        }
                        .debugBorder(showDebugBorders, color: .purple)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.top, toastInsets.top)
                .padding(.leading, toastInsets.leading)
                .padding(.trailing, toastInsets.trailing)
                .padding(.bottom, toastInsets.bottom + bottomRowHeight + bubbleSpacing)
                .debugBorder(showDebugBorders, color: .cyan)
            }
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 12) {
            DaddyView(model: daddyModel, size: 126, onSettingsTap: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            })
            .debugBorder(showDebugBorders, color: .red)

            if !socket.appState.subAgents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(socket.appState.subAgents) { agent in
                            EmojiView(
                                emoji: "🦞",
                                state: agent.state,
                                size: 44,
                                showsGlow: false,
                                taskDescription: agent.taskDescription,
                                onTap: agent.state == "waiting_for_input" ? {
                                    pendingInputAgentId = agent.id
                                    showingInput = true
                                } : nil
                            )
                            .debugBorder(showDebugBorders, color: .yellow)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: socket.appState.subAgents.map(\.id))
                    .debugBorder(showDebugBorders, color: .green)
                }
                .frame(maxWidth: 160)
                .debugBorder(showDebugBorders, color: .pink)
                .transition(.opacity)
            }
        }
        .padding(bottomRowPadding)
        .debugBorder(showDebugBorders, color: .mint)
        .animation(.easeInOut(duration: 0.3), value: socket.appState.subAgents.isEmpty)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: BottomRowHeightKey.self, value: proxy.size.height)
            }
        )
    }

    private func appendBubble(text: String, isInteractive: Bool, agentId: String?) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            let item = BubbleItem(id: UUID().uuidString, text: text, isInteractive: isInteractive, agentId: agentId)
            bubbles.append(item)
            if bubbles.count > maxBubbles {
                let overflow = bubbles.count - maxBubbles
                for _ in 0..<overflow {
                    if let index = bubbles.firstIndex(where: { !$0.isInteractive }) {
                        bubbles.remove(at: index)
                    } else {
                        bubbles.removeFirst()
                    }
                }
            }
        }
    }

    private func upsertClawDaddyBubble(text: String) {
        if let currentId = currentClawDaddyBubbleId,
           let index = bubbles.firstIndex(where: { $0.id == currentId }) {
            if text.hasPrefix(lastClawDaddyMessage) || lastClawDaddyMessage.hasPrefix(text) {
                bubbles[index] = BubbleItem(id: currentId, text: text, isInteractive: false, agentId: nil)
                lastClawDaddyMessage = text
                return
            }
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            let item = BubbleItem(id: UUID().uuidString, text: text, isInteractive: false, agentId: nil)
            currentClawDaddyBubbleId = item.id
            lastClawDaddyMessage = text
            bubbles.append(item)
            if bubbles.count > maxBubbles {
                let overflow = bubbles.count - maxBubbles
                for _ in 0..<overflow {
                    if let index = bubbles.firstIndex(where: { !$0.isInteractive }) {
                        if bubbles[index].id == currentClawDaddyBubbleId {
                            currentClawDaddyBubbleId = nil
                        }
                        bubbles.remove(at: index)
                    } else {
                        bubbles.removeFirst()
                    }
                }
            }
        }
    }

    private func seedBubblesForLayoutTest() {
        bubbles = [
            BubbleItem(id: "selftest-1", text: "SELFTEST: 1 — short", isInteractive: false, agentId: nil),
            BubbleItem(id: "selftest-2", text: "SELFTEST: 2 — medium length line to check wrapping behavior.", isInteractive: false, agentId: nil),
            BubbleItem(id: "selftest-3", text: "SELFTEST: 3 — longer text that should wrap across multiple lines so we can validate the stack height and clipping behavior.", isInteractive: false, agentId: nil),
            BubbleItem(id: "selftest-4", text: "SELFTEST: 4 — last bubble should sit closest to ClawDaddy.", isInteractive: false, agentId: nil)
        ]
    }

    private func seedSubAgentsForSelfTest() {
        let now = ISO8601DateFormatter().string(from: Date())
        socket.appState = AppState(
            clawdaddy: .empty,
            subAgents: [
                SubAgentState(
                    id: "selftest-working",
                    state: "working",
                    taskDescription: "Searching the depths",
                    question: nil, result: nil, error: nil,
                    updatedAt: now
                ),
                SubAgentState(
                    id: "selftest-waiting",
                    state: "waiting_for_input",
                    taskDescription: "Needs your input",
                    question: "What bait should I use?",
                    result: nil, error: nil,
                    updatedAt: now
                ),
                SubAgentState(
                    id: "selftest-done",
                    state: "done",
                    taskDescription: "Finished scouting",
                    question: nil,
                    result: "Found 3 treasure chests!",
                    error: nil,
                    updatedAt: now
                ),
                SubAgentState(
                    id: "selftest-error",
                    state: "error",
                    taskDescription: "Failed mission",
                    question: nil, result: nil,
                    error: "Lost the anchor!",
                    updatedAt: now
                ),
            ]
        )
        updateSubAgentBubbles(socket.appState.subAgents)
    }

    private func updateSubAgentBubbles(_ agents: [SubAgentState]) {
        let ids = Set(agents.map { $0.id })
        lastAgentMessages = lastAgentMessages.filter { ids.contains($0.key) }
        lastAgentStates = lastAgentStates.filter { ids.contains($0.key) }
        var didTriggerReaction = false

        for agent in agents {
            let previousState = lastAgentStates[agent.id]
            if !didTriggerReaction, previousState != agent.state {
                switch agent.state {
                case "working":
                    daddyModel.send(.reaction(.perk))
                    didTriggerReaction = true
                case "waiting_for_input":
                    daddyModel.send(.reaction(.alert))
                    didTriggerReaction = true
                case "done":
                    daddyModel.send(.reaction(.settle))
                    didTriggerReaction = true
                case "error":
                    daddyModel.send(.reaction(.alert))
                    didTriggerReaction = true
                default:
                    break
                }
            }

            guard let message = messageFor(agent) else {
                lastAgentStates[agent.id] = agent.state
                continue
            }
            if lastAgentMessages[agent.id] == message, lastAgentStates[agent.id] == agent.state {
                continue
            }
            lastAgentMessages[agent.id] = message
            lastAgentStates[agent.id] = agent.state
            appendBubble(
                text: message,
                isInteractive: agent.state == "waiting_for_input",
                agentId: agent.id
            )
        }
    }

    private func resetSleepTimer() {
        isSleeping = false
        sleepTask?.cancel()
        sleepTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
            await MainActor.run { isSleeping = true }
        }
    }

    private func handleMilestone(_ reward: MilestoneReward?, delay: Double) {
        guard let reward else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            appendBubble(text: reward.message, isInteractive: false, agentId: nil)
            if let emote = reward.emote {
                daddyModel.send(.emote(emote))
            }
            if reward.salute {
                daddyModel.send(.salute)
            }
            if reward.dance {
                daddyModel.send(.dance)
            }
        }
    }

    private func messageFor(_ agent: SubAgentState) -> String? {
        switch agent.state {
        case "waiting_for_input":
            return agent.question
        case "done":
            return agent.result
        case "error":
            return agent.error
        default:
            return nil
        }
    }
}
