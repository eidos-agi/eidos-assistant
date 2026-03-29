import Foundation

struct Note: Codable, Identifiable {
    let id: UUID
    var text: String
    let timestamp: Date
    var isPinned: Bool
    var recordingDuration: TimeInterval
    var hasReminder: Bool

    var wordCount: Int {
        text.split(separator: " ").count
    }

    var dayKey: String {
        let cal = Calendar.current
        if cal.isDateInToday(timestamp) { return "Today" }
        if cal.isDateInYesterday(timestamp) { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        return fmt.string(from: timestamp)
    }

    init(text: String, recordingDuration: TimeInterval = 0) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.isPinned = false
        self.recordingDuration = recordingDuration
        // Auto-detect reminder intent
        let lower = text.lowercased()
        self.hasReminder = lower.hasPrefix("remind me") || lower.hasPrefix("reminder")
    }
}
