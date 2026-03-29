import SwiftUI

struct FloatingRecorderView: View {
    @EnvironmentObject var recorder: AudioRecorderService

    var body: some View {
        HStack(spacing: 8) {
            if recorder.isRecording {
                // Level meter bars
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(barColor(index: i))
                            .frame(width: 3, height: barHeight(index: i))
                    }
                }
                .frame(width: 20, height: 20)

                Text(formatDuration(recorder.recordingDuration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)

                // Warning pulse at 5 min
                if recorder.durationWarningShown {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }

                Spacer()

                // Current mic name
                Text(recorder.currentInputName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text("ESC cancel")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if recorder.isTranscribing {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Transcribing (first time may download model)...")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.orange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    private func barHeight(index: Int) -> CGFloat {
        let threshold = Float(index) / 5.0
        let level = recorder.audioLevel
        if level > threshold {
            return CGFloat(8 + (level - threshold) * 24)
        }
        return 4
    }

    private func barColor(index: Int) -> Color {
        let threshold = Float(index) / 5.0
        if recorder.audioLevel > threshold {
            return index >= 4 ? .red : index >= 3 ? .orange : .green
        }
        return .gray.opacity(0.3)
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        let tenths = Int(t * 10) % 10
        if mins > 0 {
            return String(format: "%d:%02d.%d", mins, secs, tenths)
        }
        return String(format: "%d.%d", secs, tenths)
    }
}
