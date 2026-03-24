// =============================================================================
// TranscriptionController.swift — WhisperKit transcription engine
// =============================================================================
//
// Uses WhisperKit (Core ML + Neural Engine) to transcribe audio locally.
// The model (openai_whisper-tiny.en) is downloaded from HuggingFace on first
// run and cached at ~/Documents/huggingface/. Subsequent launches use the
// on-disk Core ML cache — fast, no network required.
//
// A single WhisperKit instance is kept alive for the lifetime of the app
// inside a Swift actor (WhisperActor). The actor serialises all transcription
// calls, so concurrent presses simply queue rather than race. Keeping the
// instance alive means the ANE session is never torn down between calls,
// which eliminates the ANE-resource-contention hang seen when a fresh instance
// was created per call (the previous instance's ANE session wasn't fully
// released before the next init began).
//
// Completion is always called on the main queue.
// =============================================================================

import Foundation
import WhisperKit

/// Thread-safe flag that can be set exactly once. Returns true on the first call to set().
private final class Done: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func set() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !fired else { return false }
        fired = true; return true
    }
}

// ---------------------------------------------------------------------------
// MARK: - WhisperActor — serialises all kit operations on its own executor
// ---------------------------------------------------------------------------

private actor WhisperActor {

    private var kit: WhisperKit?

    // Greedy English, no fallback retries, clean output.
    private static let decodingOptions = DecodingOptions(
        task: .transcribe,
        language: "en",
        temperature: 0.0,
        temperatureFallbackCount: 0,
        skipSpecialTokens: true,
        withoutTimestamps: true,
        noSpeechThreshold: 1.0
    )

    /// Load model on first call; subsequent calls return immediately.
    func warmUp() async throws {
        guard kit == nil else { return }
        NSLog("[FreeVoice] WhisperActor: loading model…")
        kit = try await WhisperKit(model: "openai_whisper-tiny.en")
        NSLog("[FreeVoice] WhisperActor: model ready")
    }

    /// Transcribe audio file. Reuses the persistent kit instance.
    func transcribe(audioPath: String) async throws -> String {
        if kit == nil { try await warmUp() }
        guard let k = kit else {
            throw TranscriptionController.EngineError.notLoaded
        }

        // Validate audio file before sending to WhisperKit.
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioPath)[.size] as? Int) ?? 0
        NSLog("[FreeVoice] WhisperActor: transcribing %@ (%d bytes)",
              (audioPath as NSString).lastPathComponent, fileSize)

        if fileSize < 1_000 {
            NSLog("[FreeVoice] WhisperActor: audio file too small (%d bytes), skipping", fileSize)
            return ""
        }

        let results: [TranscriptionResult] = try await k.transcribe(
            audioPath: audioPath,
            decodeOptions: Self.decodingOptions
        )
        NSLog("[FreeVoice] WhisperActor: done — %d result(s)", results.count)
        return results.map { $0.text }.joined(separator: " ")
    }

}

// ---------------------------------------------------------------------------
// MARK: - TranscriptionController — public singleton
// ---------------------------------------------------------------------------

final class TranscriptionController {

    static let shared = TranscriptionController()
    private init() {}

    // MARK: - Model state

    enum ModelState { case idle, downloading, ready, failed }

    static let modelDownloadingNotification = Notification.Name("FreeVoiceModelDownloading")
    static let modelReadyNotification       = Notification.Name("FreeVoiceModelReady")

    private(set) var modelState: ModelState = .idle

    // MARK: - Types

    enum Outcome {
        case success(String)
        case failure(String)
    }

    enum EngineError: Error {
        case notLoaded
    }

    // MARK: - Private state

    private var whisper = WhisperActor()
    private var prepareTask: Task<Void, Error>?

    // MARK: - Public

    /// Warms up the model in the background. Safe to call multiple times.
    func prepare() {
        guard prepareTask == nil else { return }
        DispatchQueue.main.async {
            self.modelState = .downloading
            NotificationCenter.default.post(
                name: TranscriptionController.modelDownloadingNotification, object: nil)
        }
        prepareTask = Task {
            do {
                try await whisper.warmUp()
                DispatchQueue.main.async {
                    self.modelState = .ready
                    NotificationCenter.default.post(
                        name: TranscriptionController.modelReadyNotification, object: nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self.modelState = .failed
                    self.prepareTask = nil  // allow retry on next transcription attempt
                }
                throw error
            }
        }
    }

    func transcribe(url: URL, completion: @escaping (Outcome) -> Void) {
        if prepareTask == nil { prepare() }
        let prep = prepareTask!

        let done            = Done()
        let capturedWhisper = whisper

        // GCD watchdog — fires on the main queue after 60 s independently of
        // the Swift concurrency scheduler (which can be starved by blocked ANE threads).
        // 60 s gives plenty of headroom for long-but-legitimate recordings (~30 s audio
        // takes ~10 s to decode on tiny.en) while still catching true ANE deadlocks.
        let watchdog = DispatchWorkItem { [weak self] in
            NSLog("[FreeVoice] WATCHDOG FIRED — done=%d", done.set() ? 1 : 0)
            guard let self else { return }
            NSLog("[FreeVoice] Transcription timed out — replacing WhisperKit")
            self.whisper      = WhisperActor()  // abandon stuck instance, fresh start
            self.prepareTask  = nil
            completion(.failure("Transcription timed out. Try again."))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: watchdog)

        Task {
            do {
                try await prep.value
                let raw = try await capturedWhisper.transcribe(audioPath: url.path)
                watchdog.cancel()
                guard done.set() else { return }
                let cleaned = clean(raw)
                NSLog("[FreeVoice] Transcript: \"%@\"", cleaned)
                DispatchQueue.main.async {
                    completion(cleaned.isEmpty
                        ? .failure("Transcription produced no output.")
                        : .success(cleaned))
                }
            } catch {
                watchdog.cancel()
                guard done.set() else { return }
                NSLog("[FreeVoice] Transcription error: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    completion(.failure("Transcription failed: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - Output cleaning

    private func clean(_ raw: String) -> String {
        // Strip WhisperKit special tokens like [Music], [Applause], [BLANK_AUDIO], etc.
        let noTokens = raw.replacingOccurrences(
            of: #"\[[^\]]+\]"#, with: "", options: .regularExpression)
        return noTokens
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
