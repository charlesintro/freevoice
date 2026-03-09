// =============================================================================
// RecordingController.swift — AVAudioRecorder wrapper
// =============================================================================
//
// Records 16 kHz mono PCM to /tmp/freevoice_recording.wav.
// Requests microphone permission on first call (shows TCC prompt).
//
// All public methods are safe to call from any queue.
// Internal AVAudioRecorder work happens on the main queue.
// =============================================================================

import AVFoundation

final class RecordingController {

    // Output file — same path as v1 so whisper-cli invocation is identical.
    static let recordingURL = URL(fileURLWithPath: "/tmp/freevoice_recording.wav")

    private var recorder: AVAudioRecorder?

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
        guard let rec = recorder, rec.isRecording else { return nil }
        rec.stop()
        recorder = nil
        NSLog("[FreeVoice] Recording stopped → %@", Self.recordingURL.path)
        return Self.recordingURL
    }

    /// Stops and deletes the temporary recording file (Esc / cancel path).
    func discardRecording() {
        recorder?.stop()
        recorder = nil
        try? FileManager.default.removeItem(at: Self.recordingURL)
        NSLog("[FreeVoice] Recording discarded.")
    }

    var isRecording: Bool { recorder?.isRecording == true }

    // MARK: - Private

    private func beginRecording(completion: (Bool) -> Void) {
        // Delete any stale temp file from a previous run.
        try? FileManager.default.removeItem(at: Self.recordingURL)

        // 16-bit PCM, 16 kHz, mono — matches whisper-cli's expected input.
        let settings: [String: Any] = [
            AVFormatIDKey:            Int(kAudioFormatLinearPCM),
            AVSampleRateKey:          16_000.0,
            AVNumberOfChannelsKey:    1,
            AVLinearPCMBitDepthKey:   16,
            AVLinearPCMIsFloatKey:    false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            recorder = try AVAudioRecorder(url: Self.recordingURL, settings: settings)
            recorder?.record()
            NSLog("[FreeVoice] Recording started → %@", Self.recordingURL.path)
            completion(true)
        } catch {
            NSLog("[FreeVoice] AVAudioRecorder error: %@", error.localizedDescription)
            recorder = nil
            completion(false)
        }
    }
}
