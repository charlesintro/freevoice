// =============================================================================
// RecordingController.swift — AVAudioEngine recorder with device selection
// =============================================================================
//
// Records 16 kHz mono PCM to /tmp/freevoice_recording.wav.
// Uses AVAudioEngine so a specific input device can be selected per-app
// without affecting the system default (AVAudioRecorder cannot do this).
//
// Device selection: reads PreferencesStore.shared.inputDeviceUID at the
// start of each recording. Empty UID = use system default input.
//
// When the system audio device changes mid-recording (e.g. AirPods connect),
// the engine is restarted transparently with the new device. The output file
// stays open so the recording continues with a brief gap rather than cancelling.
//
// All public methods are safe to call from any queue.
// =============================================================================

import AVFoundation
import CoreAudio

final class RecordingController {

    // Output file — same path as v1 so whisper-cli invocation is identical.
    static let recordingURL = URL(fileURLWithPath: "/tmp/freevoice_recording.wav")

    // Notification posted ~10x/second during recording with userInfo["level": Float (RMS 0..1)]
    static let audioLevelNotification = Notification.Name("FreeVoiceAudioLevel")

    private var engine     = AVAudioEngine()
    private var outputFile: AVAudioFile?
    private var targetFormat: AVAudioFormat?

    // MARK: - Public API

    /// Requests microphone permission (if needed) then starts recording.
    /// `completion` is called on the main queue with `true` if recording started.
    func startRecording(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard granted else {
                    NSLog("[FreeVoice] Microphone permission denied.")
                    completion(false)
                    return
                }
                self?.beginRecording(completion: completion)
            }
        }
    }

    /// Stops the current recording and returns the URL of the recorded file,
    /// or nil if no recording was in progress.
    @discardableResult
    func stopRecording() -> URL? {
        guard outputFile != nil else { return nil }
        tearDownEngine()
        outputFile = nil
        NSLog("[FreeVoice] Recording stopped → %@", Self.recordingURL.path)
        return Self.recordingURL
    }

    /// Stops and deletes the temporary recording file (Esc / cancel path).
    func discardRecording() {
        tearDownEngine()
        outputFile = nil
        try? FileManager.default.removeItem(at: Self.recordingURL)
        NSLog("[FreeVoice] Recording discarded.")
    }

    var isRecording: Bool { outputFile != nil }

    // MARK: - Private

    private func tearDownEngine() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        NotificationCenter.default.removeObserver(
            self, name: .AVAudioEngineConfigurationChange, object: engine)
    }

    private func beginRecording(completion: (Bool) -> Void) {
        // Delete any stale temp file from a previous run.
        try? FileManager.default.removeItem(at: Self.recordingURL)

        // Target format is fixed regardless of input device.
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate:   16_000,
            channels:     1,
            interleaved:  true
        ) else {
            NSLog("[FreeVoice] Failed to create target audio format.")
            completion(false)
            return
        }
        targetFormat = fmt

        do {
            outputFile = try AVAudioFile(forWriting: Self.recordingURL,
                                         settings:   fmt.settings,
                                         commonFormat: .pcmFormatInt16,
                                         interleaved:  true)
        } catch {
            NSLog("[FreeVoice] AVAudioFile init error: %@", error.localizedDescription)
            completion(false)
            return
        }

        do {
            try startEngine()
            NSLog("[FreeVoice] Recording started → %@", Self.recordingURL.path)
            completion(true)
        } catch {
            NSLog("[FreeVoice] AVAudioEngine start error: %@", error.localizedDescription)
            outputFile = nil
            completion(false)
        }
    }

    /// Creates a fresh engine, installs a tap, and starts it.
    /// Called on initial start and again after each device-change restart.
    private func startEngine() throws {
        engine = AVAudioEngine()

        // Set preferred input device if the user selected one.
        let uid = PreferencesStore.shared.inputDeviceUID
        if !uid.isEmpty, let deviceID = AudioDeviceHelper.deviceID(forUID: uid) {
            do {
                try engine.inputNode.auAudioUnit.setDeviceID(deviceID)
                engine.prepare()
                NSLog("[FreeVoice] Recording using device UID: %@", uid)
            } catch {
                NSLog("[FreeVoice] Could not set input device (%@), using system default: %@",
                      uid, error.localizedDescription)
            }
        }

        let inputNode  = engine.inputNode
        let hwFormat   = inputNode.outputFormat(forBus: 0)
        guard let targetFormat else { return }
        let converter  = AVAudioConverter(from: hwFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self, let converter else { return }

            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / hwFormat.sampleRate
            )
            guard frameCapacity > 0,
                  let converted = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                   frameCapacity: frameCapacity)
            else { return }

            var isDone = false
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if isDone { outStatus.pointee = .noDataNow; return nil }
                isDone = true
                outStatus.pointee = .haveData
                return buffer
            }

            do {
                _ = converter.convert(to: converted, error: nil, withInputFrom: inputBlock)
                try self.outputFile?.write(from: converted)
            } catch {
                NSLog("[FreeVoice] Audio write error: %@", error.localizedDescription)
            }

            // RMS level for menu bar visualisation (~10 fps)
            if let data = converted.int16ChannelData?[0], converted.frameLength > 0 {
                let n = Int(converted.frameLength)
                var sum: Float = 0
                for i in 0..<n { let s = Float(data[i]) / 32768.0; sum += s * s }
                let rms = sqrt(sum / Float(n))
                DispatchQueue.main.async { [weak self] in
                    guard self != nil else { return }
                    NotificationCenter.default.post(
                        name: RecordingController.audioLevelNotification,
                        object: nil, userInfo: ["level": rms])
                }
            }
        }

        // Listen for device changes on this engine instance.
        // When triggered, seamlessly restart with the new device while keeping
        // the output file open so the recording continues uninterrupted.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.outputFile != nil else { return }
            NSLog("[FreeVoice] Audio device changed — restarting engine.")
            self.tearDownEngine()
            do {
                try self.startEngine()
                NSLog("[FreeVoice] Engine restarted with new device.")
            } catch {
                NSLog("[FreeVoice] Could not restart engine: %@", error.localizedDescription)
                self.discardRecording()
            }
        }

        try engine.start()
    }
}
