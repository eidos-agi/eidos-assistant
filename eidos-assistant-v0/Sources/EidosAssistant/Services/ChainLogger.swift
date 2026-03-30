import Foundation
import SwiftUI

/// Logs every step of the recording chain so you can see exactly where it breaks.
/// Entries are visible in the app's Debug tab and written to chain.log on disk.
@MainActor
class ChainLogger: ObservableObject {
    static let shared = ChainLogger()

    @Published var entries: [ChainLogEntry] = []

    private let logFileURL: URL
    private let maxEntries = 200

    struct ChainLogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let step: String
        let status: Status
        let detail: String

        enum Status: String {
            case ok = "OK"
            case fail = "FAIL"
            case info = "INFO"
            case start = "START"
        }

        var icon: String {
            switch status {
            case .ok: return "checkmark.circle.fill"
            case .fail: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            case .start: return "arrow.right.circle.fill"
            }
        }

        var color: Color {
            switch status {
            case .ok: return .green
            case .fail: return .red
            case .info: return .secondary
            case .start: return .blue
            }
        }
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("eidos-assistant")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logFileURL = dir.appendingPathComponent("chain.log")
        loadFromDisk()
    }

    private func loadFromDisk() {
        guard let text = try? String(contentsOf: logFileURL, encoding: .utf8) else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(maxEntries)
        for line in lines {
            // Parse: [HH:mm:ss.SSS] [STATUS] step — detail
            let str = String(line)
            guard str.count > 16,
                  let statusEnd = str.range(of: "] ", range: str.index(str.startIndex, offsetBy: 15)..<str.endIndex) else { continue }
            let statusStr = String(str[str.index(str.startIndex, offsetBy: 15)..<statusEnd.lowerBound])
            let rest = String(str[statusEnd.upperBound...])
            let parts = rest.split(separator: " — ", maxSplits: 1)
            let step = String(parts.first ?? "")
            let detail = parts.count > 1 ? String(parts[1]) : ""
            let status: ChainLogEntry.Status = {
                switch statusStr {
                case "OK": return .ok
                case "FAIL": return .fail
                case "START": return .start
                default: return .info
                }
            }()
            let timeStr = String(str[str.index(str.startIndex, offsetBy: 1)..<str.index(str.startIndex, offsetBy: 13)])
            let timestamp = fmt.date(from: timeStr) ?? Date()
            entries.append(ChainLogEntry(timestamp: timestamp, step: step, status: status, detail: detail))
        }
        entries.reverse() // Newest first
    }

    func log(_ step: String, status: ChainLogEntry.Status, detail: String = "") {
        let entry = ChainLogEntry(timestamp: Date(), step: step, status: status, detail: detail)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast()
        }

        // Also write to disk
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(fmt.string(from: entry.timestamp))] [\(status.rawValue)] \(step)\(detail.isEmpty ? "" : " — \(detail)")\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }

    func clear() {
        entries.removeAll()
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    /// Run startup health checks — non-blocking
    func runHealthChecks() {
        log("Health check", status: .start)

        // 1. Voice directory writable
        let voiceDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("eidos-assistant/voice/recordings")
        if FileManager.default.isWritableFile(atPath: voiceDir.path) {
            log("Voice directory", status: .ok, detail: "writable")
        } else {
            try? FileManager.default.createDirectory(at: voiceDir, withIntermediateDirectories: true)
            log("Voice directory", status: FileManager.default.isWritableFile(atPath: voiceDir.path) ? .ok : .fail,
                detail: voiceDir.path)
        }

        // 2. Whisper available (async — don't block launch)
        log("Whisper", status: .info, detail: "checking...")
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", "python3 -c 'from faster_whisper import WhisperModel; print(\"ok\")' 2>&1"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            await MainActor.run {
                if output.contains("ok") {
                    self.log("Whisper (faster-whisper)", status: .ok)
                } else {
                    self.log("Whisper (faster-whisper)", status: .fail, detail: "not importable")
                }
            }
        }

        // 3. Accessibility permission
        let trusted = AXIsProcessTrusted()
        log("Accessibility", status: trusted ? .ok : .info,
            detail: trusted ? "granted" : "not granted — Cmd+E works in-app only")

        // 4. Daemon socket
        let socketExists = FileManager.default.fileExists(atPath: "/tmp/eidos-assistant.sock")
        log("Daemon", status: socketExists ? .ok : .info,
            detail: socketExists ? "connected" : "not running — classification skipped")

        // 5. Omni registration
        let omniPath = NSHomeDirectory() + "/.config/eidosomni/adapters.d/voice.json"
        log("Omni", status: FileManager.default.fileExists(atPath: omniPath) ? .ok : .info,
            detail: FileManager.default.fileExists(atPath: omniPath) ? "registered" : "not registered")

        log("Health check", status: .ok, detail: "complete")
    }
}
