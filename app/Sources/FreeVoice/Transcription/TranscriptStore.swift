// =============================================================================
// TranscriptStore.swift — Persist transcripts to ~/.freevoice/
// =============================================================================
//
// Keeps the same file paths and log format as v1 (freevoice.sh) so users
// who switch from v1 to the native app keep their transcript history.
//
//   ~/.freevoice/last_transcript.txt  — single file, last result only
//   ~/.freevoice/transcripts.log      — append-only, timestamped
//
// All methods are safe to call from any queue; file I/O runs synchronously
// on the caller's queue (call from a background queue if latency matters).
// =============================================================================

import Foundation

final class TranscriptStore {

    // MARK: - Paths

    private let dataDir: URL
    private let lastTranscriptURL: URL
    private let logURL: URL

    init() {
        dataDir           = FileManager.default.homeDirectoryForCurrentUser
                              .appendingPathComponent(".freevoice")
        lastTranscriptURL = dataDir.appendingPathComponent("last_transcript.txt")
        logURL            = dataDir.appendingPathComponent("transcripts.log")
        ensureDataDir()
    }

    // MARK: - Public

    /// Persists a transcript: overwrites last_transcript.txt and appends to transcripts.log.
    func save(_ text: String) {
        // last_transcript.txt — overwrite
        do {
            try text.write(to: lastTranscriptURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("[FreeVoice] TranscriptStore: failed to write last_transcript.txt: %@",
                  error.localizedDescription)
        }

        // transcripts.log — append  [YYYY-MM-DD HH:MM:SS] <text>\n
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: "T", with: " ")
            .replacingOccurrences(of: "Z", with: "")
        let line = "[\(timestamp)] \(text)\n"
        if let data = line.data(using: .utf8) {
            appendData(data, to: logURL)
        }

        NSLog("[FreeVoice] TranscriptStore: saved transcript (%d chars).", text.count)
    }

    /// Returns the last `limit` transcripts from transcripts.log, newest last.
    func loadRecent(limit: Int = 5) -> [String] {
        guard let raw = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let recent = Array(lines.suffix(limit))
        // Strip the leading timestamp bracket so callers get just the text.
        return recent.map { line in
            // Format: "[2024-01-01 12:00:00] The actual transcript text"
            if let range = line.range(of: "] ") {
                return String(line[range.upperBound...])
            }
            return line
        }
    }

    // MARK: - Private

    private func ensureDataDir() {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dataDir.path, isDirectory: &isDir)
        if !exists || !isDir.boolValue {
            try? FileManager.default.createDirectory(at: dataDir,
                                                     withIntermediateDirectories: true)
        }
    }

    private func appendData(_ data: Data, to url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
