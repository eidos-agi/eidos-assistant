import Foundation
import SwiftUI

@MainActor
class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var recentlyDeleted: Note?
    @Published var searchText: String = ""

    private let fileURL: URL

    /// Time window for continuation mode (30 seconds)
    private let continuationWindow: TimeInterval = 30

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("eidos-assistant", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("notes.json")
        load()
    }

    // MARK: - Filtered & grouped access

    var filteredNotes: [Note] {
        let base = searchText.isEmpty
            ? notes
            : notes.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
        // Pinned first, then by timestamp
        return base.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.timestamp > rhs.timestamp
        }
    }

    var groupedNotes: [(String, [Note])] {
        let filtered = filteredNotes
        var groups: [(String, [Note])] = []
        var currentKey = ""
        var currentNotes: [Note] = []

        for note in filtered {
            let key = note.isPinned ? "Pinned" : note.dayKey
            if key != currentKey {
                if !currentNotes.isEmpty {
                    groups.append((currentKey, currentNotes))
                }
                currentKey = key
                currentNotes = [note]
            } else {
                currentNotes.append(note)
            }
        }
        if !currentNotes.isEmpty {
            groups.append((currentKey, currentNotes))
        }
        return groups
    }

    // MARK: - Mutations

    /// Add note with continuation: if last note was < 30s ago, append instead
    func addNote(text: String, recordingDuration: TimeInterval = 0) {
        if let lastNote = notes.first,
           Date().timeIntervalSince(lastNote.timestamp) < continuationWindow {
            // Continuation mode — append to last note
            notes[0].text += "\n\n" + text
            notes[0].recordingDuration += recordingDuration
            // Re-check reminder status
            let lower = notes[0].text.lowercased()
            notes[0].hasReminder = lower.hasPrefix("remind me") || lower.hasPrefix("reminder")
        } else {
            let note = Note(text: text, recordingDuration: recordingDuration)
            notes.insert(note, at: 0)
        }
        save()
    }

    func updateNoteText(id: UUID, newText: String) {
        if let idx = notes.firstIndex(where: { $0.id == id }) {
            notes[idx].text = newText
            save()
        }
    }

    func togglePin(_ note: Note) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx].isPinned.toggle()
            save()
        }
    }

    func deleteNote(at offsets: IndexSet) {
        if let first = offsets.first {
            recentlyDeleted = notes[first]
        }
        notes.remove(atOffsets: offsets)
        save()
    }

    func deleteNote(id: UUID) {
        if let idx = notes.firstIndex(where: { $0.id == id }) {
            recentlyDeleted = notes[idx]
            notes.remove(at: idx)
            save()
        }
    }

    func undoDelete() {
        if let note = recentlyDeleted {
            let idx = notes.firstIndex { $0.timestamp < note.timestamp } ?? notes.endIndex
            notes.insert(note, at: idx)
            recentlyDeleted = nil
            save()
        }
    }

    func clearOlderThan(days: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        notes.removeAll { $0.timestamp < cutoff && !$0.isPinned }
        save()
    }

    func copyToClipboard(_ note: Note) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.text, forType: .string)
    }

    func copyLastNoteToClipboard() {
        guard let first = notes.first else { return }
        copyToClipboard(first)
    }

    func exportAsMarkdown() -> String {
        var md = "# Eidos Voice Notes\n\n"
        for (group, groupNotes) in groupedNotes {
            md += "## \(group)\n\n"
            for note in groupNotes {
                let fmt = DateFormatter()
                fmt.dateFormat = "h:mm a"
                let time = fmt.string(from: note.timestamp)
                let dur = formatDuration(note.recordingDuration)
                md += "**\(time)** (\(dur), \(note.wordCount) words)\n\n"
                md += "\(note.text)\n\n---\n\n"
            }
        }
        return md
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        if mins > 0 { return "\(mins)m \(secs)s" }
        return "\(secs)s"
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(notes) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([Note].self, from: data) {
            notes = loaded
        }
    }
}
