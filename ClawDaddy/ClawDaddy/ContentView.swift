import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var socket = WebSocketClient()
    @StateObject private var speech = SpeechManager()

    @State private var inputText = ""
    @State private var showingInput = false
    @State private var pendingInputAgentId: String?
    @State private var wasRecording = false
    @State private var ackToken = 0
    @State private var ackStyle: AckStyle = .standard
    @State private var reactionTrigger = 0
    @State private var reactionStyle: ReactionStyle = .none
    @State private var saluteTrigger = 0
    @State private var emoteTrigger = 0
    @State private var emoteStyle: EmoteStyle = .none
    @State private var danceToken = 0
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
    @State private var commandCount = UserDefaults.standard.integer(forKey: "clawdaddy.commandCount")
    @State private var streakDays = 0
    @State private var lastColorScheme: ColorScheme?
    @State private var isTypewriterRevealing = false
    @Environment(\.colorScheme) private var colorScheme

    private let maxBubbles = 4
    private let toastInsets = EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 44)
    private let bottomRowPadding = EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 24)
    private let bubbleSpacing: CGFloat = 10
    private let showDebugBorders = false

    private let pushToTalkKeyCode: UInt16 = 59 // Left Control
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
                updateStreak()
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
                if lastTranscriptLength > 0 && lastTranscriptLength <= 36 {
                    ackStyle = .big
                } else {
                    ackStyle = .standard
                }
                ackToken += 1
                trackCommand()
            }
            wasRecording = newValue
        }
        .onChange(of: socket.appState.clawdaddy.lastResponse) { newValue in
            guard !isLayoutSelfTest, !isSubAgentSelfTest else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != lastClawDaddyMessage else { return }
            upsertClawDaddyBubble(text: trimmed)
            if socket.appState.clawdaddy.isReunion {
                triggerEmote(.surprised)
                danceToken += 1
            } else if socket.appState.clawdaddy.isGreeting {
                saluteTrigger += 1
                danceToken += 1
            }
        }
        .onChange(of: socket.appState.clawdaddy.state) { _, newValue in
            guard !isLayoutSelfTest, !isSubAgentSelfTest else { return }
            if newValue == "thinking" {
                setThinkingHold(duration: 2.0)
            }
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
                triggerReaction(.settle)
            } else {
                triggerReaction(.perk)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { _ in
            let now = Date()
            guard now.timeIntervalSince(lastWindowDragReaction) > 5 else { return }
            lastWindowDragReaction = now
            triggerReaction(.alert)
        }
    }

    private var effectiveClawDaddyState: String {
        if speech.isRecording {
            return "listening"
        }
        if let hold = thinkingHoldUntil, hold > Date() {
            return "thinking"
        }
        if speech.isSpeaking {
            return "speaking"
        }
        let socketState = socket.appState.clawdaddy.state
        if socketState == "idle" && isSleeping {
            return "sleeping"
        }
        return socketState
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
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            handleModifierEvent(event)
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { event in
            handleModifierEvent(event)
        }

        proximityMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in
            guard let window = NSApp.windows.first(where: { $0.level == .floating }) else { return }
            let cursor = NSEvent.mouseLocation
            let frame = window.frame
            let expanded = frame.insetBy(dx: -100, dy: -100)
            guard expanded.contains(cursor), !frame.contains(cursor) else { return }
            DispatchQueue.main.async {
                let now = Date()
                guard now.timeIntervalSince(lastProximityReaction) > 10 else { return }
                lastProximityReaction = now
                triggerReaction(.perk)
            }
        }
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
        if let monitor = proximityMonitor {
            NSEvent.removeMonitor(monitor)
            proximityMonitor = nil
        }
    }

    private func handleModifierEvent(_ event: NSEvent) {
        guard event.keyCode == pushToTalkKeyCode else { return }

        if event.modifierFlags.contains(.control) {
            startPushToTalk()
        } else {
            stopPushToTalk()
        }
    }

    private var visibleBubbles: [BubbleItem] {
        Array(bubbles.suffix(maxBubbles))
    }

    private var hasInteractiveBubble: Bool {
        bubbles.contains { $0.isInteractive }
    }

    private func triggerReaction(_ style: ReactionStyle) {
        reactionStyle = style
        reactionTrigger += 1
    }

    private func triggerEmote(_ style: EmoteStyle) {
        emoteStyle = style
        emoteTrigger += 1
    }

    private func setThinkingHold(duration: TimeInterval) {
        let target = Date().addingTimeInterval(duration)
        thinkingHoldUntil = target
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if thinkingHoldUntil == target {
                thinkingHoldUntil = nil
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
            triggerEmote(.wink)
            return true
        }
        if command.contains("tilt") || command.contains("head tilt") {
            triggerEmote(.tilt)
            return true
        }
        if command.contains("surprise") || command.contains("surprised") {
            triggerEmote(.surprised)
            return true
        }
        if command.contains("salute") {
            saluteTrigger += 1
            return true
        }
        if command.contains("backflip") || command.contains("flip") {
            triggerEmote(.backflip)
            return true
        }
        if command.contains("plank") || command.contains("walk") {
            triggerEmote(.plank)
            return true
        }
        if command.contains("play dead") || command.contains("dead") {
            triggerEmote(.playDead)
            return true
        }
        if command.contains("spin") {
            triggerEmote(.spin)
            return true
        }
        if command.contains("crab") || command.contains("rave") {
            triggerEmote(.crabRave)
            return true
        }
        if command.contains("dance") {
            danceToken += 1
            return true
        }
        if command.contains("nod") {
            triggerEmote(.nod)
            return true
        }
        if command.contains("shake") {
            triggerEmote(.shake)
            return true
        }
        if command.contains("bow") {
            triggerEmote(.bow)
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
            DaddyView(
                state: effectiveClawDaddyState,
                size: 126,
                jumpTrigger: ackToken,
                ackStyle: ackStyle,
                reactionStyle: reactionStyle,
                reactionTrigger: reactionTrigger,
                saluteTrigger: saluteTrigger,
                emoteStyle: emoteStyle,
                emoteTrigger: emoteTrigger,
                danceTrigger: danceToken,
                isTalking: isTypewriterRevealing
            )
            .debugBorder(showDebugBorders, color: .red)

            if !socket.appState.subAgents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(socket.appState.subAgents) { agent in
                            EmojiView(
                                emoji: "🦞",
                                state: agent.state,
                                size: 44,
                                showsGlow: false
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
                    triggerReaction(.perk)
                    didTriggerReaction = true
                case "waiting_for_input":
                    triggerReaction(.alert)
                    didTriggerReaction = true
                case "done":
                    triggerReaction(.settle)
                    didTriggerReaction = true
                case "error":
                    triggerReaction(.alert)
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

    private func updateStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let key = "clawdaddy.lastOpenDate"
        let streakKey = "clawdaddy.streakDays"

        if let lastDate = UserDefaults.standard.object(forKey: key) as? Date {
            let lastDay = calendar.startOfDay(for: lastDate)
            let diff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if diff == 1 {
                streakDays = UserDefaults.standard.integer(forKey: streakKey) + 1
            } else if diff == 0 {
                streakDays = max(1, UserDefaults.standard.integer(forKey: streakKey))
            } else {
                streakDays = 1
            }
        } else {
            streakDays = 1
        }
        UserDefaults.standard.set(today, forKey: key)
        UserDefaults.standard.set(streakDays, forKey: streakKey)
        checkStreak()
    }

    private func checkStreak() {
        let milestones: [Int: String] = [
            3: "Three days at sea, cap'n. Getting our sea legs.",
            7: "A full week on the water! Ye be a true sailor.",
            14: "Two weeks! The crew's never been sharper.",
            30: "A month! The crew salutes ye, cap'n.",
        ]
        guard let message = milestones[streakDays] else { return }
        let achieved = UserDefaults.standard.stringArray(forKey: "clawdaddy.streakMilestones") ?? []
        let key = String(streakDays)
        guard !achieved.contains(key) else { return }
        UserDefaults.standard.set(achieved + [key], forKey: "clawdaddy.streakMilestones")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            appendBubble(text: message, isInteractive: false, agentId: nil)
            if streakDays >= 30 {
                saluteTrigger += 1
                danceToken += 1
            }
        }
    }

    private func trackCommand() {
        commandCount += 1
        UserDefaults.standard.set(commandCount, forKey: "clawdaddy.commandCount")
        let milestones: [Int: (String, EmoteStyle?)] = [
            10: ("Tenth order, cap'n! The crew remembers every one.", nil),
            50: ("Fifty orders! This ship runs like clockwork.", nil),
            100: ("A hundred orders! Ye run a tight ship.", .backflip),
            500: ("Five hundred! Cap'n of the century.", .spin),
            1000: ("A THOUSAND. Captain legend.", .backflip),
        ]
        guard let (message, emote) = milestones[commandCount] else { return }
        let achieved = UserDefaults.standard.stringArray(forKey: "clawdaddy.commandMilestones") ?? []
        let key = String(commandCount)
        guard !achieved.contains(key) else { return }
        UserDefaults.standard.set(achieved + [key], forKey: "clawdaddy.commandMilestones")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            appendBubble(text: message, isInteractive: false, agentId: nil)
            if let emote {
                triggerEmote(emote)
            }
            danceToken += 1
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

private extension View {
    @ViewBuilder
    func debugBorder(_ enabled: Bool, color: Color) -> some View {
        if enabled {
            self.overlay(Rectangle().stroke(color, lineWidth: 1))
        } else {
            self
        }
    }
}

private struct BottomRowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}


struct InputSheet: View {
    @Binding var inputText: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a quick reply")
                .font(.headline)

            TextField("Type your answer...", text: $inputText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Send", action: onSubmit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct WindowConfigurator: NSViewRepresentable {
    @Binding var windowSize: CGSize
    let isInteractive: Bool

    func makeNSView(context: Context) -> WindowConfigView {
        let view = WindowConfigView()
        view.onWindowChange = { window in
            configure(window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: WindowConfigView, context: Context) {
        nsView.onWindowChange = { window in
            configure(window, coordinator: context.coordinator)
        }
        if let window = nsView.window {
            configure(window, coordinator: context.coordinator)
        }
    }

    private func configure(_ window: NSWindow, coordinator: Coordinator) {
        if !coordinator.didConfigure {
            coordinator.didConfigure = true

            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.hasShadow = false
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isRestorable = false
            window.setFrameAutosaveName("")

            let targetScreen = NSScreen.main ?? NSScreen.screens.first
            let size = preferredWindowSize(for: targetScreen)
            positionWindow(window, size: size, screen: targetScreen)
            DispatchQueue.main.async {
                if windowSize != size {
                    windowSize = size
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                positionWindow(window, size: size, screen: targetScreen)
            }
        }

        window.ignoresMouseEvents = !isInteractive
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var didConfigure = false
    }

    private func positionWindow(_ window: NSWindow, size: NSSize, screen: NSScreen?) {
        guard let screen else { return }
        window.setContentSize(size)
        let contentRect = NSRect(origin: .zero, size: size)
        let frameRect = window.frameRect(forContentRect: contentRect)
        let frame = screen.visibleFrame
        let insetX: CGFloat = 32
        let insetY: CGFloat = 32
        let origin = NSPoint(
            x: frame.maxX - frameRect.width - insetX,
            y: frame.minY + insetY
        )
        window.setFrame(NSRect(origin: origin, size: frameRect.size), display: true)
    }

    private func preferredWindowSize(for screen: NSScreen?) -> NSSize {
        guard let screen else { return NSSize(width: 320, height: 220) }
        let frame = screen.visibleFrame
        let height = max(220, frame.height * 0.5)
        return NSSize(width: 320, height: height)
    }
}

final class WindowConfigView: NSView {
    var onWindowChange: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindowChange?(window)
        }
    }
}
