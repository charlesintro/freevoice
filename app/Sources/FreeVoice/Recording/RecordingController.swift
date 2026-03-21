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

    /// Called on the main queue when the audio device changes mid-recording.
    /// HotkeyController sets this to cancel the current recording and return to idle.
    var onDeviceChange: (() -> Void)?

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
        guard engine.isRunning else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        outputFile = nil
        NSLog("[FreeVoice] Recording stopped → %@", Self.recordingURL.path)
        return Self.recordingURL
    }

    /// Stops and deletes the temporary recording file (Esc / cancel path).
    func discardRecording() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        outputFile = nil
        try? FileManager.default.removeItem(at: Self.recordingURL)
        NSLog("[FreeVoice] Recording discarded.")
    }

    var isRecording: Bool { engine.isRunning }

    // MARK: - Private

    private func beginRecording(completion: (Bool) -> Void) {
        // Delete any stale temp file from a previous run.
        try? FileManager.default.removeItem(at: Self.recordingURL)

        // Reset engine to clear any previous tap or device configuration.
        engine = AVAudioEngine()

        // When AirPods or another device connects/disconnects, AVAudioEngine posts
        // AVAudioEngineConfigurationChange. If we ignore it the tap format mismatches
        // and we either crash or write a silent/corrupt WAV that hangs WhisperKit.
        // Instead, cancel the recording cleanly so the user can try again.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.engine.isRunning else { return }
            NSLog("[FreeVoice] Audio device changed mid-recording — cancelling.")
            self.discardRecording()
            self.onDeviceChange?()
        }

        // Set preferred input device if the user selected one.
        // engine.prepare() is called after setDeviceID so the input node fully
        // reconfigures for the new device before we read its hardware format below.
        let uid = PreferencesStore.shared.inputDeviceUID
        if !uid.isEmpty, let deviceID = AudioDeviceHelper.deviceID(forUID: uid) {
            do {
                try engine.inputNode.auAudioUnit.setDeviceID(deviceID)
                engine.prepare()   // force re-init so outputFormat reflects the new device
                NSLog("[FreeVoice] Recording using device UID: %@", uid)
            } catch {
                NSLog("[FreeVoice] Could not set input device (%@), using system default: %@",
                      uid, error.localizedDescription)
            }
        }

        // Use the hardware's native format to avoid unnecessary conversion.
        // whisper-cli accepts various sample rates; we convert to 16 kHz in the tap.
        let inputNode   = engine.inputNode
        let hwFormat    = inputNode.outputFormat(forBus: 0)

        // Target format: 16-bit PCM, 16 kHz, mono — matches whisper-cli expectations.
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate:   16_000,
            channels:     1,
            interleaved:  true
        ) else {
            NSLog("[FreeVoice] Failed to create target audio format.")
            completion(false)
            return
        }

        do {
            outputFile = try AVAudioFile(forWriting: Self.recordingURL,
                                         settings:   targetFormat.settings,
                                         commonFormat: .pcmFormatInt16,
                                         interleaved:  true)
        } catch {
            NSLog("[FreeVoice] AVAudioFile init error: %@", error.localizedDescription)
            completion(false)
            return
        }

        // Install tap on the input node using the hardware format.
        // Convert each buffer to targetFormat before writing.
        let converter = AVAudioConverter(from: hwFormat, to: targetFormat)
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
                if isDone {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                isDone = true
                outStatus.pointee = .haveData
                return buffer
            }

            do {
                _ = converter.convert(to: converted, error: nil, withInputFrom: inputBlock)
                try self.outputFile?.write(from: converted)
            } catch {
                NSLog("[FreeVoice] Audio conversion/write error: %@", error.localizedDescription)
            }

            // Compute RMS and broadcast for menu bar level visualization (~10fps)
            if let data = converted.int16ChannelData?[0], converted.frameLength > 0 {
                let n = Int(converted.frameLength)
                var sum: Float = 0
                for i in 0..<n {
                    let s = Float(data[i]) / 32768.0
                    sum += s * s
                }
                let rms = sqrt(sum / Float(n))
                DispatchQueue.main.async { [weak self] in
                    guard self != nil else { return }
                    NotificationCenter.default.post(
                        name: RecordingController.audioLevelNotification,
                        object: nil,
                        userInfo: ["level": rms]
                    )
                }
            }
        }

        do {
            try engine.start()
            NSLog("[FreeVoice] Recording started → %@", Self.recordingURL.path)
            completion(true)
        } catch {
            NSLog("[FreeVoice] AVAudioEngine start error: %@", error.localizedDescription)
            inputNode.removeTap(onBus: 0)
            outputFile = nil
            completion(false)
        }
    }
}
