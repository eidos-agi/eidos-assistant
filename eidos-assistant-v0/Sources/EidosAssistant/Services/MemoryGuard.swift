import Foundation

/// Hard memory ceiling for the entire process.
/// If RAM exceeds the limit, it force-stops recording and logs a warning.
/// This prevents runaway allocation from any bug.
@MainActor
class MemoryGuard {
    static let shared = MemoryGuard()

    /// Max resident memory in bytes (150 MB — generous for a notes app)
    let maxBytes: UInt64 = 150 * 1024 * 1024

    private var watchdog: DispatchSourceTimer?

    /// Current process memory in bytes
    var currentMemoryBytes: UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    var currentMemoryMB: Double {
        Double(currentMemoryBytes) / (1024 * 1024)
    }

    var isOverLimit: Bool {
        currentMemoryBytes > maxBytes
    }

    /// Start monitoring — checks every 2 seconds
    func startWatchdog(onBreach: @escaping () -> Void) {
        guard watchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.isOverLimit {
                print("MEMORY GUARD: \(String(format: "%.0f", self.currentMemoryMB))MB exceeds \(self.maxBytes / 1024 / 1024)MB limit — triggering safety stop")
                onBreach()
            }
        }
        timer.resume()
        watchdog = timer
    }

    func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }
}
