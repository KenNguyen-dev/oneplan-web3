import AVFoundation
import Foundation

@MainActor
@Observable
final class AudioRecordingManager {
    // MARK: - Published state
    var isAuthorized = false
    var isRecording = false
    var recordingDuration: TimeInterval = 0
    var currentLevel: Float = 0       // normalized 0...1
    var levelSamples: [Float] = []    // rolling buffer for waveform bars (max ~51 entries)
    var recordedFileURL: URL?
    var error: String?

    // MARK: - Private
    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var durationTimer: Timer?
    private let maxSamples = 51  // matches waveform bar count in UI
    private let maxDuration: TimeInterval = 15

    // MARK: - Authorization

    func checkAuthorization() async {
        // Use AVAudioApplication for iOS 17+
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .granted:
            isAuthorized = true
        case .undetermined:
            isAuthorized = await AVAudioApplication.requestRecordPermission()
        default:
            isAuthorized = false
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard isAuthorized else {
            error = String(localized: "Microphone access not authorized")
            return
        }

        // Clean up any previous recording
        stopTimers()

        // Voice notes can contain sensitive content. Store them in a
        // dedicated directory under Application Support with
        // `.completeUntilFirstUserAuthentication` protection (works in
        // background while still encrypting at rest before first unlock)
        // rather than the system temp directory, which has no protection
        // attribute set.
        let fileName = "voice_\(Int(Date().timeIntervalSince1970)).m4a"
        let fileURL: URL
        do {
            fileURL = try Self.recordingsDirectory().appendingPathComponent(fileName)
        } catch {
            self.error = String(localized: "Could not prepare recordings directory")
            return
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.record()

            audioRecorder = recorder
            recordedFileURL = nil
            recordingDuration = 0
            levelSamples = []
            isRecording = true
            error = nil

            // Start level metering timer (~15Hz)
            levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateMeters()
                }
            }

            // Start duration timer (1Hz)
            durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    self.recordingDuration += 1
                    if self.recordingDuration >= self.maxDuration {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            self.error = String(localized: "Failed to start recording")
        }
    }

    func stopRecording() {
        guard isRecording, let recorder = audioRecorder else { return }

        let actualDuration = recorder.currentTime // Read BEFORE stop
        recorder.stop()
        isRecording = false
        recordedFileURL = recorder.url
        recordingDuration = actualDuration > 0 ? actualDuration : recordingDuration
        stopTimers()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Non-critical
        }
    }

    func resetRecording() {
        stopRecording()

        // Delete temp file
        if let url = recordedFileURL {
            try? FileManager.default.removeItem(at: url)
        }

        recordedFileURL = nil
        recordingDuration = 0
        levelSamples = []
        currentLevel = 0
        audioRecorder = nil
    }

    /// Read the recorded audio file as Data for upload
    func audioData() -> Data? {
        guard let url = recordedFileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Duration in whole seconds (for the API)
    var durationSeconds: Int {
        Int(recordingDuration)
    }

    // MARK: - Private

    private func updateMeters() {
        guard let recorder = audioRecorder, isRecording else { return }
        recorder.updateMeters()

        let power = recorder.averagePower(forChannel: 0) // dB, typically -160...0
        // Normalize to 0...1 range (treating -60dB as silence)
        let normalized = max(0, min(1, (power + 60) / 60))
        currentLevel = normalized

        levelSamples.append(normalized)
        if levelSamples.count > maxSamples {
            levelSamples.removeFirst()
        }
    }

    private func stopTimers() {
        levelTimer?.invalidate()
        levelTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
    }

    /// Returns the dedicated recordings directory, creating it on first use
    /// with `.completeUntilFirstUserAuthentication` protection.
    private static func recordingsDirectory() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let recordings = appSupport.appendingPathComponent("recordings", isDirectory: true)
        if !fm.fileExists(atPath: recordings.path) {
            try fm.createDirectory(
                at: recordings,
                withIntermediateDirectories: true,
                attributes: [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
                ]
            )
        }
        return recordings
    }
}
