// =============================================================================
// TranscriptionController.swift — whisper-cli subprocess wrapper
// =============================================================================
//
// Invokes whisper-cli as a child process on a background queue.
// Binary resolution order:
//   1. Bundled:  Bundle.main → whisper-cli  (Phase 5 distribution)
//   2. Homebrew: /opt/homebrew/bin/whisper-cli  (dev builds)
//   3. PATH usr: /usr/local/bin/whisper-cli
//
// Model: ~/.freevoice/models/ggml-tiny.en.bin
//        (same location as v1 so users keep their downloaded model)
//
// Completion is always called on the main queue.
// =============================================================================

import Foundation

final class TranscriptionController {

    // MARK: - Types

    enum TranscriptionResult {
        case success(String)
        case failure(String)   // human-readable error message
    }

    // MARK: - Public

    func transcribe(url: URL, completion: @escaping (TranscriptionResult) -> Void) {
        guard let binaryURL = resolveWhisperCLI() else {
            DispatchQueue.main.async {
                completion(.failure("whisper-cli not found. Install via: brew install whisper-cpp"))
            }
            return
        }

        let modelURL = modelPath()
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            DispatchQueue.main.async {
                completion(.failure("Model not found at \(modelURL.path). Run FreeVoice setup."))
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.runWhisper(binary: binaryURL, model: modelURL, audio: url)
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Private — process execution

    private func runWhisper(binary: URL, model: URL, audio: URL) -> TranscriptionResult {
        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "--model",    model.path,
            "--file",     audio.path,
            "--language", PreferencesStore.shared.language,
            "--no-timestamps",
            "--threads",  "4",
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe

        do {
            try process.run()
        } catch {
            return .failure("Failed to launch whisper-cli: \(error.localizedDescription)")
        }
        process.waitUntilExit()

        let rawOutput = String(
            data: outPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        let cleaned = clean(rawOutput)
        if cleaned.isEmpty {
            let errOutput = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            NSLog("[FreeVoice] whisper-cli stderr: %@", errOutput)
            return .failure("Transcription produced no output.")
        }
        return .success(cleaned)
    }

    // MARK: - Private — output cleaning (mirrors v1 freevoice.sh post-processing)

    /// Strips timestamps, collapses whitespace, trims.
    private func clean(_ raw: String) -> String {
        var lines = raw.components(separatedBy: .newlines)

        // Remove lines that are only a bracketed timestamp like "[00:00:00.000 --> 00:00:05.000]"
        let timestampPattern = try? NSRegularExpression(pattern: #"^\s*\[[\d:.,\s\-–>]+\]\s*$"#)
        lines = lines.filter { line in
            let range = NSRange(line.startIndex..., in: line)
            return timestampPattern?.firstMatch(in: line, range: range) == nil
        }

        // Remove whisper special tokens: <|endoftext|>, <|en|>, etc.
        lines = lines.map { $0.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression) }

        // Remove whisper special tokens like [BLANK_AUDIO], [MUSIC], etc.
        let specialPattern = try? NSRegularExpression(pattern: #"\[.*?\]"#)
        lines = lines.map { line in
            let range = NSRange(line.startIndex..., in: line)
            return specialPattern?.stringByReplacingMatches(in: line, range: range, withTemplate: "") ?? line
        }

        // Join, collapse internal whitespace, trim.
        let joined = lines.joined(separator: " ")
        let collapsed = joined.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private — binary / model resolution

    private func resolveWhisperCLI() -> URL? {
        // 1. Bundled binary (Phase 5)
        if let url = Bundle.main.url(forResource: "whisper-cli", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        // 2. Homebrew Apple Silicon
        let homebrew = URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli")
        if FileManager.default.isExecutableFile(atPath: homebrew.path) { return homebrew }
        // 3. Homebrew Intel / user-local
        let usrLocal = URL(fileURLWithPath: "/usr/local/bin/whisper-cli")
        if FileManager.default.isExecutableFile(atPath: usrLocal.path) { return usrLocal }
        return nil
    }

    private func modelPath() -> URL {
        // 1. Bundled model (distribution builds)
        if let url = Bundle.main.url(forResource: "ggml-tiny.en", withExtension: "bin") {
            return url
        }
        // 2. User-downloaded model (dev builds / power users with custom model)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".freevoice/models/ggml-tiny.en.bin")
    }
}
