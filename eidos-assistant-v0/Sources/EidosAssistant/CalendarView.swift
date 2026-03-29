import SwiftUI

/// Calendar-based note browser. Shows a month grid with dots for days that have notes.
/// Selecting a day shows that day's notes below.
struct CalendarView: View {
    @EnvironmentObject var noteStore: NoteStore
    @State private var selectedDate: Date = Date()
    @State private var displayMonth: Date = Date()

    private let calendar = Calendar.current

    var notesForSelectedDate: [Note] {
        noteStore.notes.filter {
            calendar.isDate($0.timestamp, inSameDayAs: selectedDate)
        }.sorted { $0.timestamp > $1.timestamp }
    }

    var daysWithNotes: Set<String> {
        Set(noteStore.notes.map { dayKey($0.timestamp) })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Month navigation
            HStack {
                Button(action: { shiftMonth(-1) }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthYearString(displayMonth))
                    .font(.headline)

                Spacer()

                Button(action: { shiftMonth(1) }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)

                Button("Today") {
                    displayMonth = Date()
                    selectedDate = Date()
                }
                .font(.caption)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Day headers
            HStack(spacing: 0) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)

            // Day grid
            let days = daysInMonth()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { day in
                    if let day = day {
                        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
                        let isToday = calendar.isDateInToday(day)
                        let hasNotes = daysWithNotes.contains(dayKey(day))

                        Button(action: { selectedDate = day }) {
                            VStack(spacing: 2) {
                                Text("\(calendar.component(.day, from: day))")
                                    .font(.system(.caption, design: .rounded))
                                    .fontWeight(isToday ? .bold : .regular)
                                    .foregroundColor(isSelected ? .white : isToday ? .accentColor : .primary)

                                Circle()
                                    .fill(hasNotes ? Color.accentColor : Color.clear)
                                    .frame(width: 4, height: 4)
                            }
                            .frame(width: 32, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? Color.accentColor : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 32, height: 36)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Notes for selected day
            if notesForSelectedDate.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No notes on \(dayString(selectedDate))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxHeight: 200)
            } else {
                List {
                    ForEach(notesForSelectedDate) { note in
                        NoteRowView(note: note)
                            .environmentObject(noteStore)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func daysInMonth() -> [Date?] {
        let range = calendar.range(of: .day, in: .month, for: displayMonth)!
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth))!
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth) - 1

        var days: [Date?] = Array(repeating: nil, count: weekdayOfFirst)
        for day in range {
            let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)!
            days.append(date)
        }
        // Pad to complete last week
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private func shiftMonth(_ delta: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: delta, to: displayMonth) {
            displayMonth = newMonth
        }
    }

    private func dayKey(_ date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year!)-\(comps.month!)-\(comps.day!)"
    }

    private func monthYearString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date)
    }

    private func dayString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        return fmt.string(from: date)
    }
}
