import AVFoundation
import AppKit
import CoreAudio
import Foundation

@MainActor
class AudioRecorderService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var currentInputName: String = "Default"
    @Published var availableInputs: [AudioInput] = []
    @Published var durationWarningShown = false

    private var recorder: AVAudioRecorder?
    private var displayLink: CVDisplayLink?
    private var displayTimer: DispatchSourceTimer?
    private var currentFileURL: URL?
    private var recordingStartTime: Date?

    struct AudioInput: Identifiable, Hashable {
        let id: AudioDeviceID
        let name: String
    }

    override init() {
        super.init()
        refreshInputDevices()
    }

    // MARK: - Device management

    func refreshInputDevices() {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize)

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize, &deviceIDs)

        var inputs: [AudioInput] = []
        for id in deviceIDs {
            var inputAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var bufferSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &inputAddr, 0, nil, &bufferSize) == noErr else { continue }
            let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(bufferSize))
            defer { bufferList.deallocate() }
            guard AudioObjectGetPropertyData(id, &inputAddr, 0, nil, &bufferSize, bufferList) == noErr else { continue }
            let channelCount = (0..<Int(bufferList.pointee.mNumberBuffers)).reduce(0) { sum, i in
                sum + Int(UnsafeMutableAudioBufferListPointer(bufferList)[i].mNumberChannels)
            }
            guard channelCount > 0 else { continue }

            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, &name)
            inputs.append(AudioInput(id: id, name: name as String))
        }
        availableInputs = inputs

        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultID: AudioDeviceID = 0
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, 0, nil, &defaultSize, &defaultID)
        currentInputName = inputs.first { $0.id == defaultID }?.name ?? "Default"
    }

    func setInputDevice(_ input: AudioInput) {
        var deviceID = input.id
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID)
        currentInputName = input.name
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }  // Re-entrant guard
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("eidos-\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.record()
            currentFileURL = fileURL
            isRecording = true
            recordingStartTime = Date()
            recordingDuration = 0
            durationWarningShown = false
            audioLevel = 0

            startDisplayTimer()
            refreshInputDevices()
            NSSound(named: .init("Tink"))?.play()
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecording() -> URL? {
        let duration = recordingDuration
        stopDisplayTimer()
        recorder?.stop()
        recorder = nil
        isRecording = false
        audioLevel = 0
        let url = currentFileURL
        currentFileURL = nil
        _lastRecordingDuration = duration
        NSSound(named: .init("Pop"))?.play()
        return url
    }

    private var _lastRecordingDuration: TimeInterval = 0
    var lastRecordingDuration: TimeInterval { _lastRecordingDuration }

    func cancelRecording() {
        stopDisplayTimer()
        recorder?.stop()
        recorder = nil
        isRecording = false
        audioLevel = 0
        if let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentFileURL = nil
        NSSound(named: .init("Funk"))?.play()
    }

    // MARK: - Display timer (main queue, no Task spawning)

    private func startDisplayTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(125))
        timer.setEventHandler { [weak self] in
            // Already on main queue — no Task needed
            guard let self, let start = self.recordingStartTime else { return }

            self.recordingDuration = Date().timeIntervalSince(start)

            if let rec = self.recorder {
                rec.updateMeters()
                let db = rec.averagePower(forChannel: 0)
                self.audioLevel = max(0, min(1, (db + 50) / 50))
            }

            if self.recordingDuration >= 300 && !self.durationWarningShown {
                self.durationWarningShown = true
                NSSound(named: .init("Purr"))?.play()
            }
        }
        timer.resume()
        displayTimer = timer
    }

    private func stopDisplayTimer() {
        displayTimer?.cancel()
        displayTimer = nil
        recordingStartTime = nil
    }
}
