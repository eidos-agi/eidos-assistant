import SwiftUI

/// Debug tab showing the chain log — every step of record → transcribe → classify
struct DebugView: View {
    @EnvironmentObject var chainLogger: ChainLogger

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chain Log")
                    .font(.headline)
                Spacer()
                Text("\(chainLogger.entries.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Clear") { chainLogger.clear() }
                    .font(.caption)
                Button("Health Check") { chainLogger.runHealthChecks() }
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if chainLogger.entries.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No log entries yet")
                        .foregroundColor(.secondary)
                    Text("Hold Cmd+E to record, or tap Health Check")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(chainLogger.entries) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: entry.icon)
                                .foregroundColor(entry.color)
                                .font(.caption)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(entry.step)
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(formatTime(entry.timestamp))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                if !entry.detail.isEmpty {
                                    Text(entry.detail)
                                        .font(.system(.caption2))
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return fmt.string(from: date)
    }
}
