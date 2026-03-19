// =============================================================================
// TranscriptionController.swift — WhisperKit transcription engine
// =============================================================================
//
// Uses WhisperKit (Core ML + Neural Engine) to transcribe audio locally.
// The model (openai_whisper-tiny.en) is downloaded from HuggingFace on first
// run and cached at ~/Documents/huggingface/. Subsequent launches use the
// on-disk Core ML cache — fast, no network required.
//
// A fresh WhisperKit instance is created for every transcription call.
// This avoids state-accumulation bugs seen when reusing a single instance
// across multiple calls (manifests as silent hangs on the 2nd+ call).
//
// Completion is always called on the main queue.
// =============================================================================

import Foundation
import WhisperKit

final class TranscriptionController {

    // MARK: - Singleton

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

    // MARK: - Private state

    // After first download this holds the local path so every subsequent
    // transcription can init WhisperKit directly from disk (no network).
    private var cachedModelFolder: String?
    private var prepareTask: Task<String, Error>?

    // Decoding options: greedy English, no fallback, clean output.
    // temperatureFallbackCount: 0 — disables the multi-pass retry loop that
    // can cause multi-second stalls on audio that fails quality thresholds.
    private static let decodingOptions = DecodingOptions(
        task: .transcribe,
        language: "en",
        temperature: 0.0,
        temperatureFallbackCount: 0,
        skipSpecialTokens: true,
        withoutTimestamps: true,
        noSpeechThreshold: 0.6
    )

    // MARK: - Public

    /// Downloads / verifies the model on first run. Safe to call multiple times.
    func prepare() {
        guard prepareTask == nil else { return }
        prepareTask = Task {
            DispatchQueue.main.async {
                self.modelState = .downloading
                NotificationCenter.default.post(
                    name: TranscriptionController.modelDownloadingNotification, object: nil)
            }
            do {
                // Initialise once to trigger download + Core ML compilation.
                let kit = try await WhisperKit(model: "openai_whisper-tiny.en")
                // Derive the on-disk path so future calls skip the network check.
                let folder = resolvedModelFolder(from: kit)
                DispatchQueue.main.async {
                    self.cachedModelFolder = folder
                    self.modelState = .ready
                    NotificationCenter.default.post(
                        name: TranscriptionController.modelReadyNotification, object: nil)
                }
                return folder
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
                let folder = try await withTranscriptionTimeout(seconds: 30) {
                    try await prep.value
                }
                NSLog("[FreeVoice] Transcribing with WhisperKit (folder: %@)", folder)

                // Fresh instance every call — eliminates state-reuse hangs.
                let results: [TranscriptionResult] = try await withTranscriptionTimeout(seconds: 30) {
                    let kit = try await WhisperKit(modelFolder: folder)
                    return try await kit.transcribe(
                        audioPath: url.path,
                        decodeOptions: TranscriptionController.decodingOptions
                    )
                }
                let raw     = results.map { $0.text }.joined(separator: " ")
                let cleaned = clean(raw)
                NSLog("[FreeVoice] Transcript: \"%@\"", cleaned)
                DispatchQueue.main.async {
                    completion(cleaned.isEmpty
                        ? .failure("Transcription produced no output.")
                        : .success(cleaned))
                }
            } catch is TranscriptionTimeoutError {
                NSLog("[FreeVoice] Transcription timed out after 30s")
                DispatchQueue.main.async {
                    completion(.failure("Transcription timed out — please try again."))
                }
            } catch {
                NSLog("[FreeVoice] Transcription error: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    completion(.failure("Transcription failed: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - Timeout helper

    private struct TranscriptionTimeoutError: Error {}

    private func withTranscriptionTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TranscriptionTimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Helpers

    /// Returns the local model folder path.
    /// Prefers WhisperKit's own modelFolder URL; falls back to the known
    /// HuggingFace default download location.
    private func resolvedModelFolder(from kit: WhisperKit) -> String {
        if let url = kit.modelFolder { return url.path }
        // Fallback: reconstruct from the HuggingFace default download base.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-tiny.en")
            .path
    }

    // MARK: - Output cleaning

    private func clean(_ raw: String) -> String {
        raw.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
