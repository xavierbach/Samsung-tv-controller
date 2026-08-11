import AVFoundation
import Foundation
import Speech

/// Press-and-hold speech capture, transcribed entirely on-device so the
/// transcript is ready the instant the thumb lifts.
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isListening = false
    @Published var level: Float = 0  // mic level for the waveform

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioApplication.requestRecordPermission { _ in }
    }

    func start() {
        guard !isListening, let recognizer, recognizer.isAvailable else { return }
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true  // the latency trick
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        var bufferCount = 0
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            // crude RMS level for the halo animation — throttled so the UI
            // isn't redrawn on every audio buffer
            bufferCount += 1
            guard bufferCount % 3 == 0, let data = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            var i = 0
            while i < frames { sum += data[i] * data[i]; i += 16 }
            let rms = sqrt(sum / Float(max(frames / 16, 1)))
            Task { @MainActor in self?.level = min(rms * 12, 1) }
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            if let result {
                Task { @MainActor in self?.transcript = result.bestTranscription.formattedString }
            }
        }

        audioEngine.prepare()
        try? audioEngine.start()
        isListening = true
    }

    /// Stops capture and returns the final transcript.
    func stop() -> String {
        guard isListening else { return transcript }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        isListening = false
        level = 0
        return transcript
    }
}
