import AVFoundation
import os
import Speech
import SwiftUI

private let pttLog = Logger(subsystem: "com.teej.ClawDaddy", category: "PTT")
// pttT0 / pttMs() defined in ContentView.swift

final class SpeechManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isSpeaking = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var lastTranscript = ""
    private var onTranscript: ((String) -> Void)?
    private var isStopping = false
    private var stopWorkItem: DispatchWorkItem?

    // Voxtral realtime WebSocket state
    private var voxtralWebSocket: URLSessionWebSocketTask?
    private var voxtralReceiveTask: Task<Void, Never>?
    private var activeProvider: STTProvider = .apple
    private var voxtralApiKey: String = ""

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        speechRecognizer?.delegate = self
        synthesizer.delegate = self
    }

    /// Unified entry point — dispatches to Apple or Voxtral recording path.
    func startRecording(provider: STTProvider, apiKey: String, onResult: @escaping (String) -> Void) {
        guard !isRecording else { return }
        activeProvider = provider
        voxtralApiKey = apiKey

        switch provider {
        case .apple:
            startAppleRecording(onResult: onResult)
        case .voxtral:
            startVoxtralRecording(onResult: onResult)
        }
    }

    // MARK: - Apple STT

    private func startAppleRecording(onResult: @escaping (String) -> Void) {
        stopWorkItem?.cancel()
        stopWorkItem = nil
        onTranscript = onResult
        lastTranscript = ""
        isStopping = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        pttLog.warning("[PTT] T+\(pttMs())ms isRecording = true (Apple)")
        isRecording = true

        DispatchQueue.global(qos: .userInitiated).async {
            pttLog.warning("[PTT] T+\(pttMs())ms beginAudioCapture starting")
            self.beginAudioCapture(request: request)
            pttLog.warning("[PTT] T+\(pttMs())ms beginAudioCapture done")
        }
    }

    private func beginAudioCapture(request: SFSpeechAudioBufferRecognitionRequest) {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            DispatchQueue.main.async {
                self.finishRecording(sendTranscript: false)
            }
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                DispatchQueue.main.async {
                    self.lastTranscript = result.bestTranscription.formattedString
                }
                if result.isFinal {
                    DispatchQueue.main.async {
                        self.finishRecording(sendTranscript: true)
                    }
                }
            }
            if error != nil {
                DispatchQueue.main.async {
                    self.finishRecording(sendTranscript: true)
                }
            }
        }
    }

    // MARK: - Voxtral Realtime STT

    private func startVoxtralRecording(onResult: @escaping (String) -> Void) {
        stopWorkItem?.cancel()
        stopWorkItem = nil
        onTranscript = onResult
        lastTranscript = ""
        isStopping = false

        pttLog.warning("[PTT] T+\(pttMs())ms isRecording = true (Voxtral)")
        isRecording = true

        DispatchQueue.global(qos: .userInitiated).async {
            self.beginVoxtralRealtimeCapture()
        }
    }

    private var voxtralChunkCount = 0

    private func beginVoxtralRealtimeCapture() {
        // 1. Open WebSocket with Bearer auth
        let url = URL(string: "wss://api.mistral.ai/v1/audio/transcriptions/realtime?model=voxtral-mini-transcribe-realtime-2602")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(voxtralApiKey)", forHTTPHeaderField: "Authorization")

        let ws = URLSession.shared.webSocketTask(with: request)
        voxtralWebSocket = ws
        ws.resume()
        voxtralChunkCount = 0

        // 2. Start receive loop — audio capture begins on session.created
        voxtralReceiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    guard let ws = self?.voxtralWebSocket else { break }
                    let message = try await ws.receive()
                    switch message {
                    case .string(let text):
                        self?.handleVoxtralEvent(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self?.handleVoxtralEvent(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        pttLog.error("[PTT] Voxtral WS receive error: \(error.localizedDescription)")
                        DispatchQueue.main.async { self?.finishRecording(sendTranscript: true) }
                    }
                    break
                }
            }
        }
    }

    /// Start audio engine + tap only after the server confirms the session is ready.
    private func startVoxtralAudioCapture() {
        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            pttLog.error("[PTT] Failed to create target audio format")
            DispatchQueue.main.async { self.finishRecording(sendTranscript: false) }
            return
        }

        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            pttLog.error("[PTT] Failed to create audio converter")
            DispatchQueue.main.async { self.finishRecording(sendTranscript: false) }
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self, let ws = self.voxtralWebSocket else { return }
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * 16000.0 / hardwareFormat.sampleRate
            )
            guard frameCount > 0,
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if let error {
                pttLog.error("[PTT] Audio conversion error: \(error.localizedDescription)")
                return
            }
            guard let channelData = convertedBuffer.int16ChannelData else { return }
            let byteCount = Int(convertedBuffer.frameLength) * 2
            let pcmData = Data(bytes: channelData[0], count: byteCount)
            let b64 = pcmData.base64EncodedString()
            let json = "{\"type\":\"input_audio.append\",\"audio\":\"\(b64)\"}"
            ws.send(.string(json)) { sendError in
                if let sendError {
                    pttLog.error("[PTT] Voxtral WS send error: \(sendError.localizedDescription)")
                }
            }
            self.voxtralChunkCount += 1
            if self.voxtralChunkCount == 1 {
                pttLog.warning("[PTT] Voxtral first audio chunk sent (\(byteCount) bytes)")
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            pttLog.warning("[PTT] Voxtral audio engine started")
        } catch {
            pttLog.error("[PTT] Audio engine start failed: \(error.localizedDescription)")
            DispatchQueue.main.async { self.finishRecording(sendTranscript: false) }
        }
    }

    private func handleVoxtralEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            pttLog.warning("[PTT] Voxtral WS: unparseable event")
            return
        }

        switch type {
        case "session.created":
            pttLog.warning("[PTT] Voxtral session created — starting audio capture")
            DispatchQueue.global(qos: .userInitiated).async {
                self.startVoxtralAudioCapture()
            }
        case "transcription.text.delta":
            if let delta = json["text"] as? String {
                DispatchQueue.main.async {
                    self.lastTranscript += delta
                }
            }
        case "transcription.done":
            pttLog.warning("[PTT] Voxtral transcription done (chunks sent: \(self.voxtralChunkCount), event: \(text.prefix(200)))")
            // Server closes the connection after this — cancel receive loop to avoid spurious errors
            voxtralReceiveTask?.cancel()
            voxtralReceiveTask = nil
        case "error":
            let msg = (json["message"] as? String) ?? "unknown"
            pttLog.error("[PTT] Voxtral WS error event: \(msg)")
            DispatchQueue.main.async { self.finishRecording(sendTranscript: true) }
        default:
            pttLog.warning("[PTT] Voxtral WS unknown event: \(type)")
        }
    }

    private func teardownVoxtralWebSocket() {
        voxtralReceiveTask?.cancel()
        voxtralReceiveTask = nil
        voxtralWebSocket?.cancel(with: .normalClosure, reason: nil)
        voxtralWebSocket = nil
    }

    // MARK: - Common

    func stopRecording() {
        stopRecording(after: 0)
    }

    func stopRecording(after delay: TimeInterval) {
        stopWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishRecording(sendTranscript: true)
        }
        stopWorkItem = workItem
        if delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }

    private func finishRecording(sendTranscript: Bool) {
        if isStopping {
            return
        }
        isStopping = true
        stopWorkItem?.cancel()
        stopWorkItem = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        if activeProvider == .voxtral {
            // Send end-of-audio signal, then wait briefly for final deltas
            voxtralWebSocket?.send(.string("{\"type\":\"input_audio.end\"}")) { [weak self] error in
                if let error {
                    pttLog.error("[PTT] Voxtral WS send end error: \(error.localizedDescription)")
                }
                // Give the server a moment to flush final text_delta events
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.deliverVoxtralResult(sendTranscript: sendTranscript)
                }
            }
            return
        }

        let transcript = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        lastTranscript = ""
        isRecording = false

        if sendTranscript, !transcript.isEmpty {
            onTranscript?(transcript)
        }
        onTranscript = nil
        isStopping = false
    }

    private func deliverVoxtralResult(sendTranscript: Bool) {
        teardownVoxtralWebSocket()

        let transcript = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        lastTranscript = ""
        isRecording = false

        if sendTranscript, !transcript.isEmpty {
            onTranscript?(transcript)
        }
        onTranscript = nil
        isStopping = false
    }
}

extension SpeechManager: SFSpeechRecognizerDelegate {}

extension SpeechManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}
