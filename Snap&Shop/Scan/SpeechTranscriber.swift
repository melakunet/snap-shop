import AVFoundation
import Combine
import Speech
import Foundation

/// Handles on-device speech recognition for live voice hints (microphone → searchQuery)
/// and file-based transcription for imported video audio (on-device first, Groq fallback).
///
/// Live mic path:   audio processed entirely on-device via AVAudioEngine + SFSpeechRecognizer.
/// Video file path: SFSpeechURLRecognitionRequest (on-device) → BackendClient.transcribeAudio (Groq).
@MainActor
final class SpeechTranscriber: ObservableObject {
    enum Phase: Equatable {
        case idle
        case requestingPermission
        case listening
        case processingFile
        case done(String)
        case unavailable(String)
    }

    @Published var phase: Phase = .idle
    @Published var partialTranscript: String = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: — Live mic

    func startListening() {
        guard case .idle = phase else { return }
        phase = .requestingPermission
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard status == .authorized else {
                    self.phase = .unavailable("Speech recognition was denied. Enable it in Settings → Privacy → Speech Recognition.")
                    return
                }
                self.beginCapture()
            }
        }
    }

    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        if case .listening = phase {
            let final = partialTranscript
            phase = final.isEmpty ? .idle : .done(final)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func reset() {
        stopListening()
        phase = .idle
        partialTranscript = ""
    }

    // MARK: — Video audio

    /// Transcribe audio from an imported video URL.
    /// 1. On-device via SFSpeechURLRecognitionRequest (private, no network).
    /// 2. Groq Whisper fallback via BackendClient.transcribeAudio (audio track only, ≤25 MB).
    func transcribeVideoAudio(url: URL) async {
        phase = .processingFile
        partialTranscript = ""

        // Both SFSpeechURLRecognitionRequest and AVAssetExportSession raise an
        // uncatchable NSException when the asset has zero audio tracks. Check once
        // here before either path runs; skip transcription silently if no track found.
        let asset = AVURLAsset(url: url)
        guard let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
              !audioTracks.isEmpty else {
            phase = .idle
            return
        }

        if let text = await transcribeFileOnDevice(url: url), !text.isEmpty {
            partialTranscript = text
            phase = .done(text)
            return
        }

        if let text = try? await BackendClient.transcribeAudio(videoURL: url), !text.isEmpty {
            partialTranscript = text
            phase = .done(text)
            return
        }

        phase = .idle
    }

    // MARK: — Private

    private func beginCapture() {
        guard let recognizer, recognizer.isAvailable else {
            phase = .unavailable("Speech recognition is not available on this device.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        // On-device recognition where supported — audio never leaves the device.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = true

        let engine = AVAudioEngine()
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            phase = .unavailable("Could not start microphone: \(error.localizedDescription)")
            return
        }

        audioEngine = engine
        recognitionRequest = request
        phase = .listening
        partialTranscript = ""

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.partialTranscript = text
                    if result.isFinal {
                        self.phase = .done(text)
                        self.cleanupEngine()
                        return
                    }
                }
                if let error {
                    // kAFAssistantErrorDomain: 216 = cancelled, 1110 = no speech detected
                    let nsErr = error as NSError
                    let isExpected = nsErr.code == 216 || nsErr.code == 1110 || nsErr.code == 203
                    if case .listening = self.phase {
                        let final = self.partialTranscript
                        self.phase = isExpected
                            ? (final.isEmpty ? .idle : .done(final))
                            : (final.isEmpty ? .unavailable("Recognition failed.") : .done(final))
                    }
                    self.cleanupEngine()
                }
            }
        }
    }

    private func transcribeFileOnDevice(url: URL) async -> String? {
        guard let recognizer, recognizer.isAvailable else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = false
        return await withCheckedContinuation { continuation in
            var done = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !done else { return }
                if let result, result.isFinal {
                    done = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    done = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func cleanupEngine() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
