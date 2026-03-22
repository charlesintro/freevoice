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
        noSpeechThreshold: 0.6
    )

    /// Load model on first call; subsequent calls return immediately.
    /// Uses cached model folder directly to avoid network call on cold start.
    func warmUp() async throws {
        guard kit == nil else { return }
        NSLog("[FreeVoice] WhisperActor: loading model…")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let cachedPath = docs
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-tiny.en")
            .path
        if FileManager.default.fileExists(atPath: cachedPath) {
            NSLog("[FreeVoice] WhisperActor: using cached model at %@", cachedPath)
            kit = try await WhisperKit(modelFolder: cachedPath)
        } else {
            NSLog("[FreeVoice] WhisperActor: downloading model…")
            kit = try await WhisperKit(model: "openai_whisper-tiny.en")
        }
        NSLog("[FreeVoice] WhisperActor: model ready")
    }

    /// Transcribe audio file. Reuses the persistent kit instance.
    func transcribe(audioPath: String) async throws -> String {
        if kit == nil { try await warmUp() }
        guard let k = kit else {
            throw TranscriptionController.EngineError.notLoaded
        }
        NSLog("[FreeVoice] WhisperActor: transcribing %@", (audioPath as NSString).lastPathComponent)
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

    private let whisper = WhisperActor()
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
                DispatchQueue.main.async { self.modelState = .failed }
                throw error
            }
        }
    }

    func transcribe(url: URL, completion: @escaping (Outcome) -> Void) {
        if prepareTask == nil { prepare() }
        let prep = prepareTask!
        Task {
            do {
                // Wait for model to be ready (instant after first load).
                try await prep.value
                // Actor serialises the transcribe call — second press queues here.
                let raw     = try await whisper.transcribe(audioPath: url.path)
                let cleaned = clean(raw)
                NSLog("[FreeVoice] Transcript: \"%@\"", cleaned)
                DispatchQueue.main.async {
                    completion(cleaned.isEmpty
                        ? .failure("Transcription produced no output.")
                        : .success(cleaned))
                }
            } catch {
                NSLog("[FreeVoice] Transcription error: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    completion(.failure("Transcription failed: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - Output cleaning

    private func clean(_ raw: String) -> String {
        raw.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
