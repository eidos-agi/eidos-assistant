import Foundation

/// Sends transcribed notes to eidos-assistant-daemon for intelligent routing.
/// Falls back gracefully if daemon isn't running — notes still save locally.
class DaemonClient {
    static let shared = DaemonClient()
    private let socketPath = "/tmp/eidos-assistant.sock"

    var isDaemonRunning: Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    /// Send a note to the daemon for classification and routing.
    /// Non-blocking. Returns routing result or nil if daemon unavailable.
    func routeNote(text: String, uuid: String? = nil) async -> DaemonRouteResult? {
        guard isDaemonRunning else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [socketPath] in
                let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { close(fd) }

                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)
                withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                    socketPath.withCString { cstr in
                        _ = memcpy(ptr, cstr, min(socketPath.count, 104))
                    }
                }

                let connectResult = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }

                guard connectResult == 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                // Build safe JSON payload
                let sanitized = text
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                    .replacingOccurrences(of: "\t", with: "\\t")
                let uuidField = uuid.map { ", \"uuid\": \"\($0)\"" } ?? ""
                let payload = "{\"text\": \"\(sanitized)\"\(uuidField)}\n"
                _ = payload.withCString { send(fd, $0, payload.count, 0) }

                // Read response (30s timeout)
                var tv = timeval(tv_sec: 30, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                var buffer = [UInt8](repeating: 0, count: 4096)
                let bytesRead = recv(fd, &buffer, buffer.count, 0)

                if bytesRead > 0,
                   let response = String(bytes: buffer[0..<bytesRead], encoding: .utf8),
                   let data = response.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let result = DaemonRouteResult(
                        routedTo: json["routed"] as? String ?? "unknown",
                        text: json["text"] as? String ?? "",
                        error: json["error"] as? String
                    )
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

struct DaemonRouteResult {
    let routedTo: String
    let text: String
    let error: String?
}
