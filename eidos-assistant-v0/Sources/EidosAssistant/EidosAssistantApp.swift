import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

@main
struct EidosAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Main window — full Dock app
        WindowGroup("Eidos Assistant") {
            MainWindowView()
                .environmentObject(appDelegate.noteStore)
                .environmentObject(appDelegate.recorder)
                .environmentObject(appDelegate)
                .environmentObject(appDelegate.chainLogger)
        }
        .defaultSize(width: 520, height: 600)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.recorder)
                .environmentObject(appDelegate)
        }
    }
}

// MARK: - Main Window

struct MainWindowView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var recorder: AudioRecorderService
    @EnvironmentObject var appDelegate: AppDelegate
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Recording status bar (always visible)
            RecordingStatusBar()
                .environmentObject(recorder)
                .environmentObject(appDelegate)

            Divider()

            // Tab picker
            Picker("View", selection: $selectedTab) {
                Label("Notes", systemImage: "list.bullet").tag(0)
                Label("Calendar", systemImage: "calendar").tag(1)
                Label("Export", systemImage: "square.and.arrow.up").tag(2)
                Label("Debug", systemImage: "ant.fill").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Tab content
            switch selectedTab {
            case 0:
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search notes...", text: $noteStore.searchText)
                        .textFieldStyle(.plain)
                    if !noteStore.searchText.isEmpty {
                        Button(action: { noteStore.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                if noteStore.filteredNotes.isEmpty {
                    EmptyStateView(hasSearch: !noteStore.searchText.isEmpty)
                } else {
                    NoteListView()
                        .environmentObject(noteStore)
                }

                Divider()
                BottomToolbar()
                    .environmentObject(noteStore)

            case 1:
                CalendarView()
                    .environmentObject(noteStore)

            case 2:
                ExportView()
                    .environmentObject(noteStore)

            case 3:
                DebugView()
                    .environmentObject(ChainLogger.shared)

            default:
                EmptyView()
            }
        }
        .frame(minWidth: 480, minHeight: 500)
        .onAppear {
            appDelegate.registerHotkeys()
        }
    }
}

// MARK: - Recording Status Bar

struct RecordingStatusBar: View {
    @EnvironmentObject var recorder: AudioRecorderService
    @EnvironmentObject var appDelegate: AppDelegate

    var body: some View {
        HStack(spacing: 10) {
            if recorder.isRecording {
                // Level meter
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(index: i))
                            .frame(width: 4, height: barHeight(index: i))
                    }
                }
                .frame(width: 28, height: 24)

                Text(formatDuration(recorder.recordingDuration))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundColor(.red)

                if recorder.durationWarningShown {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }

                Spacer()

                Text(recorder.currentInputName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Button("Cancel (ESC)") {
                    appDelegate.performCancel()
                }
                .font(.caption)

                Button("Stop") {
                    Task { await appDelegate.performStopAndTranscribe() }
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .tint(.red)

            } else if recorder.isTranscribing {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Transcribing with Whisper...")
                    .foregroundColor(.orange)
                Spacer()
            } else {
                Image(systemName: "mic")
                    .foregroundColor(.secondary)
                Text("Hold \u{2318}\(appDelegate.hotkeyChar.uppercased()) to record (walkie-talkie)")
                    .foregroundColor(.secondary)
                Spacer()
                Button("Hold to Record") {
                    appDelegate.recorder.startRecording()
                    appDelegate.floatingPanel.show(recorder: appDelegate.recorder)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(recorder.isRecording ? Color.red.opacity(0.08) : Color.clear)
    }

    private func barHeight(index: Int) -> CGFloat {
        let threshold = Float(index) / 5.0
        let level = recorder.audioLevel
        if level > threshold {
            return CGFloat(6 + (level - threshold) * 30)
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
        if mins > 0 { return String(format: "%d:%02d.%d", mins, secs, tenths) }
        return String(format: "%d.%d", secs, tenths)
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let hasSearch: Bool

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: hasSearch ? "magnifyingglass" : "mic.badge.plus")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(hasSearch ? "No matching notes" : "No notes yet")
                .font(.headline)
                .foregroundColor(.secondary)
            if !hasSearch {
                Text("Hold \u{2318}E to record — release to save")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }
}

// MARK: - Notes List

struct NoteListView: View {
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        List {
            ForEach(noteStore.groupedNotes, id: \.0) { group, notes in
                Section(group) {
                    ForEach(notes) { note in
                        NoteRowView(note: note)
                            .environmentObject(noteStore)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}

struct NoteRowView: View {
    let note: Note
    @EnvironmentObject var noteStore: NoteStore
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Badges
            HStack(spacing: 6) {
                if note.isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                if note.hasReminder {
                    Label("Reminder", systemImage: "bell.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }

            // Text
            if isEditing {
                TextEditor(text: $editText)
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 150)
                HStack {
                    Button("Save") { commitEdit() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Cancel") { isEditing = false }
                        .controlSize(.small)
                }
            } else {
                Text(note.text)
                    .font(.body)
                    .lineLimit(8)
                    .textSelection(.enabled)
            }

            // Metadata row
            HStack(spacing: 12) {
                Text(Self.staticTimestamp(note.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if note.recordingDuration > 0 {
                    Label(formatDuration(note.recordingDuration), systemImage: "waveform")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("\(note.wordCount) words")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .draggable(note.text)
        .contextMenu {
            Button("Copy") { noteStore.copyToClipboard(note) }
            Button(note.isPinned ? "Unpin" : "Pin") { noteStore.togglePin(note) }
            Button("Edit") {
                editText = note.text
                isEditing = true
            }
            Divider()
            Button("Delete", role: .destructive) { noteStore.deleteNote(id: note.id) }
        }
    }

    private func commitEdit() {
        noteStore.updateNoteText(id: note.id, newText: editText)
        isEditing = false
    }

    static func staticTimestamp(_ date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 60 { return "just now" }
        if delta < 3600 { return "\(Int(delta / 60))m ago" }
        let cal = Calendar.current
        let fmt = DateFormatter()
        if cal.isDateInToday(date) {
            fmt.dateFormat = "h:mm a"
            return fmt.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            fmt.dateFormat = "'Yesterday' h:mm a"
            return fmt.string(from: date)
        }
        fmt.dateFormat = "MMM d, h:mm a"
        return fmt.string(from: date)
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        if mins > 0 { return "\(mins)m \(secs)s" }
        return "\(secs)s"
    }
}

// MARK: - Bottom Toolbar

struct BottomToolbar: View {
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        HStack {
            if let _ = noteStore.recentlyDeleted {
                Button("Undo Delete") { noteStore.undoDelete() }
                    .font(.caption)
            }
            Spacer()
            Text("\(noteStore.notes.count) notes")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Menu {
                Button("Export as Markdown...") { exportMarkdown() }
                Divider()
                Menu("Clear Old Notes") {
                    Button("Older than 7 days") { noteStore.clearOlderThan(days: 7) }
                    Button("Older than 30 days") { noteStore.clearOlderThan(days: 30) }
                    Button("Older than 90 days") { noteStore.clearOlderThan(days: 90) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func exportMarkdown() {
        let md = noteStore.exportAsMarkdown()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "eidos-notes.md"
        if panel.runModal() == .OK, let url = panel.url {
            try? md.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var recorder: AudioRecorderService
    @EnvironmentObject var appDelegate: AppDelegate
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch { print("Launch at login error: \(error)") }
                    }
            }

            Section("Whisper Model") {
                Picker("Model", selection: $appDelegate.whisperModel) {
                    Text("tiny (fast, rough)").tag("tiny")
                    Text("base").tag("base")
                    Text("small").tag("small")
                    Text("medium").tag("medium")
                    Text("large-v3-turbo (best)").tag("large-v3-turbo")
                }
                .pickerStyle(.radioGroup)
            }

            Section("Hotkey") {
                Picker("Record hotkey", selection: $appDelegate.hotkeyChar) {
                    Text("\u{2318}E").tag("e")
                    Text("\u{2318}R").tag("r")
                    Text("\u{2318}U").tag("u")
                    Text("\u{2318}J").tag("j")
                }
            }

            Section("Audio Input") {
                Picker("Microphone", selection: Binding(
                    get: { recorder.currentInputName },
                    set: { name in
                        if let input = recorder.availableInputs.first(where: { $0.name == name }) {
                            recorder.setInputDevice(input)
                        }
                    }
                )) {
                    ForEach(recorder.availableInputs) { input in
                        Text(input.name).tag(input.name)
                    }
                }
                Button("Refresh Devices") { recorder.refreshInputDevices() }
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            recorder.refreshInputDevices()
        }
    }
}

// MARK: - Accessibility Guide

struct AccessibilityGuideView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Accessibility Permission Needed")
                .font(.headline)
            Text("Eidos Assistant needs Accessibility permission to capture the global hotkey when other apps are focused.")
                .font(.body)
                .multilineTextAlignment(.center)
            Button("Open System Settings") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            Text("After granting, restart the app.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(32)
        .frame(width: 400)
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let noteStore = NoteStore()
    let recorder = AudioRecorderService()
    let floatingPanel = FloatingPanelController()
    let chainLogger = ChainLogger.shared

    @Published var whisperModel: String = "large-v3-turbo"
    @Published var hotkeyChar: String = "e"

    private var accessibilityWindow: NSWindow?
    private var hotkeysRegistered = false
    private var pttActive = false  // True from key-down to key-up — prevents re-entry
    private var daemonProcess: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationService.shared.requestPermission()
        loadPreferences()
        checkAccessibility()
        registerHotkeys()
        registerWithOmni()
        startDaemon()
        chainLogger.runHealthChecks()

        // RAM watchdog — if memory exceeds 150MB, force-stop everything
        MemoryGuard.shared.startWatchdog { [weak self] in
            guard let self else { return }
            if self.recorder.isRecording {
                self.recorder.cancelRecording()
                self.floatingPanel.hide()
                self.pttActive = false
            }
            self.recorder.isTranscribing = false
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopDaemon()
    }

    // MARK: - Daemon lifecycle

    private func startDaemon() {
        // Find daemon.py — check next to app, then in known dev location
        let candidates = [
            Bundle.main.bundlePath + "/Contents/Resources/daemon.py",
            NSHomeDirectory() + "/repos-eidos-agi/eidos-assistant/eidos-assistant-daemon/daemon.py"
        ]
        guard let daemonPath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            print("Daemon not found — classification will be skipped")
            return
        }

        // Don't start if already running
        let pidFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("eidos-assistant/daemon.pid")
        if FileManager.default.fileExists(atPath: pidFile.path),
           let pidStr = try? String(contentsOf: pidFile),
           let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
            // Check if process is actually running
            if kill(pid, 0) == 0 {
                print("Daemon already running (PID: \(pid))")
                return
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "python3 '\(daemonPath)'"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            daemonProcess = process
            print("Daemon started (PID: \(process.processIdentifier))")
        } catch {
            print("Failed to start daemon: \(error)")
        }
    }

    private func stopDaemon() {
        if let process = daemonProcess, process.isRunning {
            process.terminate()
            print("Daemon stopped")
        }
        daemonProcess = nil
    }

    // MARK: - Preferences

    private func loadPreferences() {
        if let model = UserDefaults.standard.string(forKey: "whisperModel") {
            whisperModel = model
        }
        if let key = UserDefaults.standard.string(forKey: "hotkeyChar") {
            hotkeyChar = key
        }
    }

    func savePreferences() {
        UserDefaults.standard.set(whisperModel, forKey: "whisperModel")
        UserDefaults.standard.set(hotkeyChar, forKey: "hotkeyChar")
    }

    // MARK: - Omni adapter registration

    /// Register the voice adapter with omni's adapter registry.
    /// Writes a manifest to ~/.config/eidosomni/adapters.d/voice.json
    /// Omni discovers it automatically. Users configure nothing.
    private func registerWithOmni() {
        // Adapter code path — in .app bundle or dev source tree
        let bundledAdapter = Bundle.main.bundlePath + "/Contents/Resources/omni-adapter/voice.py"
        let devAdapter = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/omni-adapter/voice.py").path
        let adapterPath = FileManager.default.fileExists(atPath: bundledAdapter) ? bundledAdapter : devAdapter

        let dataDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("eidos-assistant/voice").path

        let home = NSHomeDirectory()
        let registryDir = "\(home)/.config/eidosomni/adapters.d"
        let manifestPath = "\(registryDir)/voice.json"
        let timestamp = ISO8601DateFormatter().string(from: Date())

        // Use Process to write manifest — avoids JSONSerialization nesting issues
        let script = """
        mkdir -p '\(registryDir)' && python3 -c "
        import json
        m = {
            'name': 'voice',
            'version': '0.1.0',
            'description': 'Voice notes from Eidos Assistant',
            'adapter': {'module': 'voice', 'path': '\(adapterPath)'},
            'data_dir': '\(dataDir)',
            'uri_scheme': 'voice://',
            'source_name': 'voice',
            'sync_interval': 60,
            'registered_by': 'com.eidos.assistant',
            'registered_at': '\(timestamp)'
        }
        with open('\(manifestPath)', 'w') as f:
            json.dump(m, f, indent=2)
        "
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        try? process.run()
    }

    // MARK: - Accessibility

    private func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            chainLogger.log("Accessibility", status: .info, detail: "Not granted — grant in System Settings > Privacy > Accessibility")
        }
    }

    // MARK: - Hotkeys (Push-to-Talk: hold Cmd+E to record, release to stop)

    func registerHotkeys() {
        guard !hotkeysRegistered else { return }
        hotkeysRegistered = true

        // KEY DOWN — start recording (PTT style)
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKeyDown(event) }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            Task { @MainActor in self.handleKeyDown(event) }
            if self.shouldConsumeEvent(event) { return nil }
            return event
        }

        // KEY UP — stop recording and transcribe (PTT release)
        NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor in self?.handleKeyUp(event) }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            Task { @MainActor in self.handleKeyUp(event) }
            return event
        }

        // FLAGS CHANGED — detect Cmd release while holding E
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
            return event
        }
    }

    private func shouldConsumeEvent(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags
        let chars = event.charactersIgnoringModifiers ?? ""
        if mods.contains(.command) && !mods.contains(.shift) && chars == hotkeyChar { return true }
        if mods.contains(.command) && mods.contains(.shift) && chars == "v" { return true }
        if event.keyCode == 53 && recorder.isRecording { return true }
        return false
    }

    @MainActor
    private func handleKeyDown(_ event: NSEvent) {
        let mods = event.modifierFlags
        let chars = event.charactersIgnoringModifiers ?? ""

        // Cmd+hotkey DOWN: start recording
        // pttActive is the ONLY guard — isARepeat is unreliable for global monitors
        if mods.contains(.command) && !mods.contains(.shift) && chars == hotkeyChar {
            guard !pttActive else { return }  // Already recording from this PTT press
            pttActive = true
            if !recorder.isRecording && !recorder.isTranscribing {
                chainLogger.log("PTT key down", status: .start)
                recorder.startRecording()
                chainLogger.log("Recording started", status: .ok, detail: "input: \(recorder.currentInputName)")
                floatingPanel.show(recorder: recorder)
            }
            return
        }

        // Cmd+Shift+V: paste last note
        if mods.contains(.command) && mods.contains(.shift) && chars == "v" {
            noteStore.copyLastNoteToClipboard()
            NSSound(named: .init("Tink"))?.play()
            return
        }

        // Escape: cancel recording
        if event.keyCode == 53 && recorder.isRecording {
            pttActive = false
            performCancel()
        }
    }

    @MainActor
    private func handleKeyUp(_ event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? ""

        // Hotkey UP: stop recording and transcribe
        if chars == hotkeyChar && pttActive {
            pttActive = false
            if recorder.isRecording {
                Task { await performStopAndTranscribe() }
            }
        }
    }

    @MainActor
    private func handleFlagsChanged(_ event: NSEvent) {
        // Cmd released while PTT active: stop and transcribe
        if pttActive && !event.modifierFlags.contains(.command) {
            pttActive = false
            if recorder.isRecording {
                Task { await performStopAndTranscribe() }
            }
        }
    }

    // MARK: - Public actions (called from UI buttons too)

    /// Voice store root — bucket-per-recording structure for omni
    private var voiceRecordingsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("eidos-assistant/voice/recordings", isDirectory: true)
    }

    private var manifestURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("eidos-assistant/voice/manifest.jsonl")
    }

    func performStopAndTranscribe() async {
        if recorder.isRecording {
            guard let fileURL = recorder.stopRecording() else {
                chainLogger.log("Stop recording", status: .fail, detail: "no file URL returned")
                return
            }
            let duration = recorder.lastRecordingDuration
            chainLogger.log("Recording stopped", status: .ok, detail: String(format: "%.1fs, file: %@", duration, fileURL.lastPathComponent))

            // Debounce: <0.5s is a PTT accident
            if duration < 0.5 {
                chainLogger.log("Debounce", status: .info, detail: String(format: "%.2fs < 0.5s — discarded", duration))
                try? FileManager.default.removeItem(at: fileURL)
                floatingPanel.hide()
                return
            }

            recorder.isTranscribing = true
            floatingPanel.show(recorder: recorder)

            let bucketID = UUID()
            let bucketDir = voiceRecordingsDir.appendingPathComponent(bucketID.uuidString)
            chainLogger.log("Bucket", status: .start, detail: bucketID.uuidString)

            do {
                // 1. Create bucket directory
                try FileManager.default.createDirectory(at: bucketDir, withIntermediateDirectories: true)
                chainLogger.log("Bucket created", status: .ok)

                // 2. Move audio.wav into bucket
                let audioPath = bucketDir.appendingPathComponent("audio.wav")
                try FileManager.default.moveItem(at: fileURL, to: audioPath)
                let audioSize = (try? FileManager.default.attributesOfItem(atPath: audioPath.path)[.size] as? Int) ?? 0
                chainLogger.log("Audio moved", status: .ok, detail: "\(audioSize / 1024)KB")

                // 3. Transcribe → write transcript.json into bucket
                chainLogger.log("Whisper", status: .start, detail: "model: \(whisperModel)")
                let transcribeStart = Date()
                let result = try await WhisperService.shared.transcribe(fileURL: audioPath, model: whisperModel)
                let transcribeTime = Date().timeIntervalSince(transcribeStart)
                chainLogger.log("Whisper done", status: .ok, detail: String(format: "%.1fs — \"%@\"", transcribeTime, String(result.text.prefix(60))))

                let transcriptPath = bucketDir.appendingPathComponent("transcript.json")
                try result.rawJSON.write(to: transcriptPath, options: .atomic)

                // 4. Append to manifest.jsonl
                let manifestEntry: [String: Any] = [
                    "uuid": bucketID.uuidString,
                    "timestamp": ISO8601DateFormatter().string(from: Date()),
                    "status": "transcribed",
                    "duration_sec": duration,
                ]
                if let manifestData = try? JSONSerialization.data(withJSONObject: manifestEntry),
                   let manifestLine = String(data: manifestData, encoding: .utf8) {
                    let line = (manifestLine + "\n").data(using: .utf8)!
                    if FileManager.default.fileExists(atPath: manifestURL.path) {
                        let handle = try FileHandle(forWritingTo: manifestURL)
                        handle.seekToEndOfFile()
                        handle.write(line)
                        handle.closeFile()
                    } else {
                        try? FileManager.default.createDirectory(
                            at: manifestURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try line.write(to: manifestURL)
                    }
                }

                // 5. Update app UI
                noteStore.addNote(text: result.text, recordingDuration: duration)

                // 6. Log performance
                await PerformanceMonitor.shared.logTranscription(
                    model: whisperModel,
                    audioFileURL: audioPath,
                    audioDuration: duration,
                    transcriptionTime: transcribeTime,
                    wordCount: result.text.split(separator: " ").count
                )

                // 7. Short notes auto-copy
                let wordCount = result.text.split(separator: " ").count
                if wordCount <= 10 {
                    noteStore.copyToClipboard(noteStore.notes.first!)
                    NotificationService.shared.notifyTranscriptionComplete(
                        text: result.text + "\n(Copied to clipboard)"
                    )
                } else {
                    NotificationService.shared.notifyTranscriptionComplete(text: result.text)
                }

                // 8. Send to daemon with uuid so it writes classification.json into bucket
                let noteText = result.text
                let bucketUUID = bucketID.uuidString
                Task.detached(priority: .utility) {
                    if let routeResult = await DaemonClient.shared.routeNote(text: noteText, uuid: bucketUUID) {
                        print("Daemon routed: \(routeResult.routedTo)")
                    }
                }
            } catch {
                chainLogger.log("CHAIN FAILED", status: .fail, detail: error.localizedDescription)
                print("Transcription error: \(error)")
            }

            recorder.isTranscribing = false
            floatingPanel.hide()
        } else {
            recorder.startRecording()
            floatingPanel.show(recorder: recorder)
        }
    }

    func performCancel() {
        recorder.cancelRecording()
        floatingPanel.hide()
    }
}
