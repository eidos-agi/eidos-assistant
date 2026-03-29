import Foundation

/// Tracks performance metrics and writes them to disk for continuous improvement.
/// Every transcription logs: duration, model, file size, transcription time, word count.
/// This data feeds the improvement loop — we can spot regressions and optimize.
@MainActor
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()

    @Published var lastTranscriptionTime: TimeInterval = 0
    @Published var avgTranscriptionTime: TimeInterval = 0

    private let metricsURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("eidos-assistant", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        metricsURL = dir.appendingPathComponent("metrics.jsonl")
    }

    struct TranscriptionMetric: Codable {
        let timestamp: Date
        let model: String
        let audioFileSizeBytes: Int
        let audioDurationSec: Double
        let transcriptionTimeSec: Double
        let wordCount: Int
        let realtimeFactor: Double  // transcription_time / audio_duration (lower = faster)
    }

    func logTranscription(
        model: String,
        audioFileURL: URL,
        audioDuration: Double,
        transcriptionTime: Double,
        wordCount: Int
    ) {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioFileURL.path)[.size] as? Int) ?? 0
        let rtf = audioDuration > 0 ? transcriptionTime / audioDuration : 0

        let metric = TranscriptionMetric(
            timestamp: Date(),
            model: model,
            audioFileSizeBytes: fileSize,
            audioDurationSec: audioDuration,
            transcriptionTimeSec: transcriptionTime,
            wordCount: wordCount,
            realtimeFactor: rtf
        )

        lastTranscriptionTime = transcriptionTime

        // Append to JSONL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(metric),
           let line = String(data: data, encoding: .utf8) {
            let appendData = (line + "\n").data(using: .utf8)!
            if FileManager.default.fileExists(atPath: metricsURL.path) {
                if let handle = try? FileHandle(forWritingTo: metricsURL) {
                    handle.seekToEndOfFile()
                    handle.write(appendData)
                    handle.closeFile()
                }
            } else {
                try? appendData.write(to: metricsURL)
            }
        }

        // Update running average
        updateAverage()
    }

    private func updateAverage() {
        guard let data = try? String(contentsOf: metricsURL, encoding: .utf8) else { return }
        let lines = data.split(separator: "\n")
        let recent = lines.suffix(20) // Last 20 transcriptions
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var total: Double = 0
        var count = 0
        for line in recent {
            if let jsonData = line.data(using: .utf8),
               let metric = try? decoder.decode(TranscriptionMetric.self, from: jsonData) {
                total += metric.transcriptionTimeSec
                count += 1
            }
        }
        if count > 0 {
            avgTranscriptionTime = total / Double(count)
        }
    }

    /// Returns a summary for the improvement dashboard
    func summary() -> String {
        guard let data = try? String(contentsOf: metricsURL, encoding: .utf8) else {
            return "No metrics yet"
        }
        let lines = data.split(separator: "\n")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var totalTime: Double = 0
        var totalAudio: Double = 0
        var count = 0

        for line in lines {
            if let jsonData = line.data(using: .utf8),
               let m = try? decoder.decode(TranscriptionMetric.self, from: jsonData) {
                totalTime += m.transcriptionTimeSec
                totalAudio += m.audioDurationSec
                count += 1
            }
        }

        if count == 0 { return "No metrics yet" }
        let avgRTF = totalAudio > 0 ? totalTime / totalAudio : 0
        return "\(count) transcriptions | avg \(String(format: "%.1f", totalTime/Double(count)))s | RTF \(String(format: "%.2f", avgRTF))x"
    }
}
