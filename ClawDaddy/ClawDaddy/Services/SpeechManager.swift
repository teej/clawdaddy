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

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        speechRecognizer?.delegate = self
        synthesizer.delegate = self
    }

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    func startRecording(onResult: @escaping (String) -> Void) {
        guard !isRecording else { return }

        stopWorkItem?.cancel()
        stopWorkItem = nil
        onTranscript = onResult
        lastTranscript = ""
        isStopping = false
        pttLog.warning("[PTT] T+\(pttMs())ms isRecording = true")
        isRecording = true  // Immediate UI feedback — audio setup happens off main thread

        DispatchQueue.global(qos: .userInitiated).async {
            pttLog.warning("[PTT] T+\(pttMs())ms beginAudioCapture starting")
            self.beginAudioCapture()
            pttLog.warning("[PTT] T+\(pttMs())ms beginAudioCapture done")
        }
    }

    private func beginAudioCapture() {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
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

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.lastTranscript = result.bestTranscription.formattedString
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
