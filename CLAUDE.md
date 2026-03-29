# Eidos Assistant

Voice front-end for eidos omni. Hold Cmd+E, speak, release. Transcribed, classified, stored in recording buckets that omni indexes.

## Architecture

- `eidos-assistant-v0/` — SwiftUI Mac app (PTT recording, Whisper transcription, bucket storage)
- `eidos-assistant-daemon/` — Python daemon (Claude Agent SDK classification, writes classification.json into buckets)
- `omni-adapter/` — Omni voice adapter + adapter registry reference implementation

## Key Files

| File | Purpose |
|------|---------|
| `eidos-assistant-v0/Sources/EidosAssistant/EidosAssistantApp.swift` | App entry, views, hotkeys, recording logic (needs refactoring — 876 lines) |
| `eidos-assistant-v0/Sources/EidosAssistant/Services/AudioRecorderService.swift` | AVAudioRecorder wrapper with level metering |
| `eidos-assistant-v0/Sources/EidosAssistant/Services/WhisperService.swift` | Shells out to transcribe.py (faster-whisper) |
| `eidos-assistant-v0/Sources/EidosAssistant/Resources/transcribe.py` | Faster-whisper transcription with segment-level output |
| `eidos-assistant-daemon/daemon.py` | Claude Agent SDK daemon, Unix socket, 8 classification tools |
| `omni-adapter/voice.py` | Omni adapter: reads buckets, maps to omni resources |
| `omni-adapter/registry.py` | Adapter registry reference implementation |

## Guardrails

- Everything routes through eidos omni. No Apple services, no Supabase direct.
- Data model first, front-end second.
- Bucket structure is the contract. Audio is the source of truth, transcription is derived.
- The app works without omni installed. Omni catches up later.

## Build & Test

```bash
cd eidos-assistant-v0
swift build -c release    # build
./ci.sh test              # 10 tests
./ci.sh deploy            # package + install to /Applications
```

## Gotchas (learned the hard way)

- **Python paths:** macOS .app bundles don't inherit shell PATH/pyenv/nvm. WhisperService uses absolute path `~/.pyenv/versions/3.12.7/bin/python3`, never bare `python3`.
- **Test from the real .app, not Terminal.** Synthetic `say` audio tested from Terminal works because Terminal has PATH. The real .app doesn't. Always test from the deployed app.
- **Timers:** Use `DispatchSource.makeTimerSource(queue: .main)` for UI timers. Never `Timer.scheduledTimer` + `Task { @MainActor in }` — Tasks pile up and outlive the timer.
- **PTT guard:** Use a `pttActive` boolean flag, not `event.isARepeat`. `addGlobalMonitorForEvents` doesn't reliably set `isARepeat`.
- **Accessibility:** Use `AXIsProcessTrusted()` to check. Never `AXIsProcessTrustedWithOptions` with prompt=true — it triggers the system dialog even when already granted.
- **Chain logging:** The Debug tab (ChainLogger) logs every step of the recording chain. Read `chain.log` to see where it broke. Logs persist to `~/Library/Application Support/eidos-assistant/chain.log`.
- **Health checks must test the real code path.** The health check for Whisper used a login shell (worked). The actual transcription didn't (failed). Same code path or it's a lie.
