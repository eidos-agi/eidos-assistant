import Foundation

struct TranscriptResult {
    let text: String
    let rawJSON: Data  // Full transcript.json contents to write to bucket
}

class WhisperService {
    static let shared = WhisperService()

    private var scriptPath: String {
        let bundlePath = Bundle.main.bundlePath
        let candidates = [
            URL(fileURLWithPath: bundlePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/transcribe.py").path,
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/transcribe.py").path
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? candidates.last!
    }

    func transcribe(fileURL: URL, model: String = "large-v3-turbo") async throws -> TranscriptResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-l", "-c",
            "python3 '\(scriptPath)' '\(fileURL.path)' '\(model)'"
        ]
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()

                guard proc.terminationStatus == 0,
                      let outStr = String(data: outData, encoding: .utf8),
                      !outStr.isEmpty else {
                    let errStr = String(data: errData, encoding: .utf8) ?? "unknown error"
                    continuation.resume(throwing: WhisperError.transcriptionFailed(errStr))
                    return
                }

                // Parse JSON to extract text, but keep raw JSON for bucket
                if let jsonData = outStr.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let text = json["text"] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let result = TranscriptResult(
                        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                        rawJSON: jsonData
                    )
                    continuation.resume(returning: result)
                } else {
                    let trimmed = outStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        continuation.resume(throwing: WhisperError.emptyTranscription)
                    } else {
                        // Fallback: plain text, wrap in minimal JSON
                        let fallbackJSON = "{\"text\": \"\(trimmed)\"}".data(using: .utf8) ?? Data()
                        continuation.resume(returning: TranscriptResult(text: trimmed, rawJSON: fallbackJSON))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    enum WhisperError: LocalizedError {
        case emptyTranscription
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptyTranscription:
                return "Whisper returned empty transcription"
            case .transcriptionFailed(let output):
                return "Whisper failed: \(output)"
            }
        }
    }
}
