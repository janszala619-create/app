import AVFoundation
import Combine
import Foundation
import Speech

enum SpeechRecognitionServiceError: LocalizedError {
    case speechPermissionDenied
    case microphonePermissionDenied
    case recognizerUnavailable
    case audioEngineStartFailed(String)
    case noMicrophoneInput

    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            return "Die Berechtigung für Spracherkennung wurde nicht erteilt."
        case .microphonePermissionDenied:
            return "Die Mikrofonberechtigung wurde nicht erteilt."
        case .recognizerUnavailable:
            return "Die deutsche Spracherkennung ist gerade nicht verfügbar."
        case .audioEngineStartFailed(let message):
            return "Die Aufnahme konnte nicht gestartet werden: \(message)"
        case .noMicrophoneInput:
            return "Es wurde kein Mikrofoneingang gefunden."
        }
    }
}

@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledInputTap = false
    private var isStarting = false

    func requestPermissions() async -> Bool {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()

        if authorizationStatus == .notDetermined {
            authorizationStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }

        guard authorizationStatus == .authorized else {
            errorMessage = SpeechRecognitionServiceError.speechPermissionDenied.localizedDescription
            isRecording = false
            return false
        }

        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        guard microphoneGranted else {
            errorMessage = SpeechRecognitionServiceError.microphonePermissionDenied.localizedDescription
            isRecording = false
            return false
        }

        errorMessage = nil
        return true
    }

    func startRecording() async {
        guard !isStarting, !isRecording else {
            return
        }

        isStarting = true
        errorMessage = nil

        guard await requestPermissions() else {
            isStarting = false
            return
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = SpeechRecognitionServiceError.recognizerUnavailable.localizedDescription
            isStarting = false
            isRecording = false
            return
        }

        cancelRecognitionTask()
        stopAudioEngine()
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Datenschutz-Zusage der App: Erkennung bleibt auf dem Gerät, wann immer iOS das anbietet.
        request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        recognitionRequest = request

        do {
            try configureAudioSessionAndStartEngine(with: request)
        } catch {
            errorMessage = error.localizedDescription
            cleanupAfterStop(deactivateSession: true)
            isStarting = false
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }

                if let error {
                    self.errorMessage = error.localizedDescription
                    self.cleanupAfterStop(deactivateSession: true)
                    return
                }

                if result?.isFinal == true {
                    self.cleanupAfterStop(deactivateSession: true)
                }
            }
        }

        isRecording = true
        isStarting = false
    }

    func stopRecording() {
        guard isRecording || recognitionRequest != nil || recognitionTask != nil || audioEngine.isRunning else {
            isStarting = false
            isRecording = false
            return
        }

        recognitionRequest?.endAudio()
        stopAudioEngine()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
        isStarting = false
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancelRecording() {
        cancelRecognitionTask()
        cleanupAfterStop(deactivateSession: true)
        transcript = ""
    }

    func reset() {
        cancelRecording()
        errorMessage = nil
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    private func configureAudioSessionAndStartEngine(with request: SFSpeechAudioBufferRecognitionRequest) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw SpeechRecognitionServiceError.noMicrophoneInput
        }

        if hasInstalledInputTap {
            inputNode.removeTap(onBus: 0)
            hasInstalledInputTap = false
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        hasInstalledInputTap = true

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            throw SpeechRecognitionServiceError.audioEngineStartFailed(error.localizedDescription)
        }
    }

    private func cleanupAfterStop(deactivateSession: Bool) {
        stopAudioEngine()
        recognitionRequest = nil
        recognitionTask = nil
        isStarting = false
        isRecording = false

        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func cancelRecognitionTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    private func stopAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        if hasInstalledInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledInputTap = false
        }
    }
}
