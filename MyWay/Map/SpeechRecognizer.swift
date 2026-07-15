// Voice search for the search bar (Android's mic in SearchBar.kt used RecognizerIntent; iOS uses
// SFSpeechRecognizer + AVAudioEngine). Toggle recording; the live transcript flows into the query.
import Speech
import AVFoundation

@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var recording = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() { recording ? stop() : start() }

    func start() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else { return }
                self.begin()
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else { return }
        task?.cancel(); task = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        engine.prepare()
        try? engine.start()
        recording = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result { Task { @MainActor in self.transcript = result.bestTranscription.formattedString } }
            if error != nil || result?.isFinal == true { Task { @MainActor in self.stop() } }
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        recording = false
    }
}
