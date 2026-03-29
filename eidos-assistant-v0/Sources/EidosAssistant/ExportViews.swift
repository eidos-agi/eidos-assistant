import SwiftUI
import UniformTypeIdentifiers

/// Humanistic export options
struct ExportView: View {
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export Your Notes")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            List {
                ExportOptionRow(
                    icon: "book.fill",
                    color: .purple,
                    title: "Daily Journal",
                    description: "Today's notes woven into a flowing narrative"
                ) { exportJournal() }

                ExportOptionRow(
                    icon: "envelope.fill",
                    color: .blue,
                    title: "Letter to Future Self",
                    description: "Weekly reflection formatted as a personal letter"
                ) { exportLetter() }

                ExportOptionRow(
                    icon: "bubble.left.and.bubble.right.fill",
                    color: .green,
                    title: "Conversation Thread",
                    description: "Notes as a timestamped chat thread you can share"
                ) { exportThread() }

                ExportOptionRow(
                    icon: "point.3.connected.trianglepath.dotted",
                    color: .orange,
                    title: "Mind Map (Mermaid)",
                    description: "Connected topics as a graph you can open in Obsidian"
                ) { exportMindMap() }

                ExportOptionRow(
                    icon: "doc.plaintext.fill",
                    color: .secondary,
                    title: "Raw Markdown",
                    description: "All notes with timestamps and metadata"
                ) { exportMarkdown() }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Export implementations

    private func exportJournal() {
        let today = noteStore.notes.filter { Calendar.current.isDateInToday($0.timestamp) }
        guard !today.isEmpty else { saveFile("No notes recorded today.", name: "journal") ; return }

        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMMM d, yyyy"
        var md = "# \(fmt.string(from: Date()))\n\n"

        let sorted = today.sorted { $0.timestamp < $1.timestamp }
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"

        // Weave into narrative
        md += "Today started with a thought"
        for (i, note) in sorted.enumerated() {
            let time = timeFmt.string(from: note.timestamp)
            if i == 0 {
                md += " around \(time):\n\n> \(note.text)\n\n"
            } else if i == sorted.count - 1 {
                md += "The day wrapped up with this at \(time):\n\n> \(note.text)\n\n"
            } else {
                md += "Later, at \(time):\n\n> \(note.text)\n\n"
            }
        }
        md += "---\n*\(sorted.count) notes captured. \(sorted.reduce(0) { $0 + $1.wordCount }) words spoken.*\n"
        saveFile(md, name: "journal-\(dateStamp())")
    }

    private func exportLetter() {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let thisWeek = noteStore.notes.filter { $0.timestamp >= weekAgo }.sorted { $0.timestamp < $1.timestamp }
        guard !thisWeek.isEmpty else { saveFile("No notes this week.", name: "letter") ; return }

        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM d"
        let start = fmt.string(from: weekAgo)
        let end = fmt.string(from: Date())

        var md = "Dear future me,\n\n"
        md += "This week (\(start) – \(end)), you captured \(thisWeek.count) voice notes — "
        md += "\(thisWeek.reduce(0) { $0 + $1.wordCount }) words total. "
        md += "Here's what was on your mind:\n\n"

        // Group by day
        let grouped = Dictionary(grouping: thisWeek) { note in
            Calendar.current.startOfDay(for: note.timestamp)
        }
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEEE"

        for day in grouped.keys.sorted() {
            let notes = grouped[day]!
            md += "**\(dayFmt.string(from: day))**: "
            md += notes.map { $0.text }.joined(separator: ". ")
            md += "\n\n"
        }

        let reminders = thisWeek.filter { $0.hasReminder }
        if !reminders.isEmpty {
            md += "You had \(reminders.count) reminder(s) — make sure these got handled:\n"
            for r in reminders {
                md += "- \(r.text)\n"
            }
            md += "\n"
        }

        md += "Take care of yourself.\n\n— Past you\n"
        saveFile(md, name: "letter-\(dateStamp())")
    }

    private func exportThread() {
        let sorted = noteStore.notes.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { saveFile("No notes.", name: "thread") ; return }

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "MMM d, h:mm a"

        var md = "# Voice Notes Thread\n\n"
        var lastDay = ""

        for note in sorted {
            let day = note.dayKey
            if day != lastDay {
                md += "---\n### \(day)\n\n"
                lastDay = day
            }
            let time = timeFmt.string(from: note.timestamp)
            let pinned = note.isPinned ? " \u{1F4CC}" : ""
            let reminder = note.hasReminder ? " \u{1F514}" : ""
            md += "**[\(time)]**\(pinned)\(reminder) \(note.text)\n\n"
        }
        saveFile(md, name: "thread-\(dateStamp())")
    }

    private func exportMindMap() {
        let notes = noteStore.notes
        guard !notes.isEmpty else { saveFile("No notes.", name: "mindmap") ; return }

        // Extract keywords and cluster
        var md = "```mermaid\nmindmap\n  root((Voice Notes))\n"

        // Group by day
        let grouped = Dictionary(grouping: notes) { $0.dayKey }
        for (day, dayNotes) in grouped.sorted(by: { $0.key > $1.key }).prefix(7) {
            md += "    \(day)\n"
            for note in dayNotes.prefix(5) {
                let snippet = String(note.text.prefix(50)).replacingOccurrences(of: "\n", with: " ")
                md += "      \(snippet)\n"
            }
        }
        md += "```\n"
        saveFile(md, name: "mindmap-\(dateStamp())")
    }

    private func exportMarkdown() {
        let md = noteStore.exportAsMarkdown()
        saveFile(md, name: "eidos-notes-\(dateStamp())")
    }

    // MARK: - Helpers

    private func saveFile(_ content: String, name: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "\(name).md"
        if panel.runModal() == .OK, let url = panel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func dateStamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}

struct ExportOptionRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.down.doc")
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
