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

    private let maxBubbles = 4
    private let toastInsets = EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 44)
    private let bottomRowPadding = EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 24)
    private let bubbleSpacing: CGFloat = 10
    private let showDebugBorders = false
    private let connectedGreetings: Set<String> = [
        "Welcome aboard.",
        "Standing by at the helm.",
        "Awaiting your command.",
        "Where shall we set course?",
        "Ready for orders, Captain.",
        "Deck’s clear and ready.",
        "All systems shipshape.",
        "Set the course, Captain.",
        "At your service, Captain.",
        "What’s the plan, Captain?",
    ]

    private let pushToTalkKeyCode: UInt16 = 59 // Left Control
    private var isLayoutSelfTest: Bool {
        ProcessInfo.processInfo.environment["CLAWDADDY_LAYOUT_SELFTEST"] == "1"
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
            } else if !isUITest {
                speech.requestAuthorization()
                socket.connect()
                startKeyMonitor()
            }
        }
        .onDisappear {
            stopKeyMonitor()
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
            }
            if wasRecording, !newValue {
                if lastTranscriptLength > 0 && lastTranscriptLength <= 36 {
                    ackStyle = .big
                } else {
                    ackStyle = .standard
                }
                ackToken += 1
            }
            wasRecording = newValue
        }
        .onChange(of: socket.appState.clawdaddy.lastResponse) { newValue in
            guard !isLayoutSelfTest else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != lastClawDaddyMessage else { return }
            upsertClawDaddyBubble(text: trimmed)
            if connectedGreetings.contains(trimmed) {
                saluteTrigger += 1
                danceToken += 1
            }
        }
        .onChange(of: socket.appState.clawdaddy.state) { _, newValue in
            guard !isLayoutSelfTest else { return }
            if newValue == "thinking" {
                setThinkingHold(duration: 2.0)
            }
        }
        .onReceive(socket.$appState) { newState in
            guard !isLayoutSelfTest else { return }
            if newState.clawdaddy.lastResponse.isEmpty, newState.subAgents.isEmpty {
                bubbles.removeAll()
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
        return socket.appState.clawdaddy.state
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
            speech.stopRecording(after: 0.25)
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
    }

    private func stopKeyMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
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
        } else if tokens.first == "wink" || tokens.first == "tilt" || tokens.first == "surprised" || tokens.first == "surprise" || tokens.first == "salute" {
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
                            isInteractive: bubble.isInteractive
                        ) {
                            if bubble.isInteractive {
                                pendingInputAgentId = bubble.agentId
                                showingInput = true
                            }
                        }
                        .debugBorder(showDebugBorders, color: .purple)
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
                danceTrigger: danceToken
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
                        }
                    }
                    .debugBorder(showDebugBorders, color: .green)
                }
                .frame(maxWidth: 160)
                .debugBorder(showDebugBorders, color: .pink)
            }
        }
        .padding(bottomRowPadding)
        .debugBorder(showDebugBorders, color: .mint)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: BottomRowHeightKey.self, value: proxy.size.height)
            }
        )
    }

    private func appendBubble(text: String, isInteractive: Bool, agentId: String?) {
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

    private func upsertClawDaddyBubble(text: String) {
        if let currentId = currentClawDaddyBubbleId,
           let index = bubbles.firstIndex(where: { $0.id == currentId }) {
            if text.hasPrefix(lastClawDaddyMessage) || lastClawDaddyMessage.hasPrefix(text) {
                bubbles[index] = BubbleItem(id: currentId, text: text, isInteractive: false, agentId: nil)
                lastClawDaddyMessage = text
                return
            }
        }

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

    private func seedBubblesForLayoutTest() {
        bubbles = [
            BubbleItem(id: "selftest-1", text: "SELFTEST: 1 — short", isInteractive: false, agentId: nil),
            BubbleItem(id: "selftest-2", text: "SELFTEST: 2 — medium length line to check wrapping behavior.", isInteractive: false, agentId: nil),
            BubbleItem(id: "selftest-3", text: "SELFTEST: 3 — longer text that should wrap across multiple lines so we can validate the stack height and clipping behavior.", isInteractive: false, agentId: nil),
            BubbleItem(id: "selftest-4", text: "SELFTEST: 4 — last bubble should sit closest to ClawDaddy.", isInteractive: false, agentId: nil)
        ]
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
