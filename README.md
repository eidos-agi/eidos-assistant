# Eidos Assistant

Voice front-end for [eidos omni](https://github.com/eidos-agi/eidosomni) — the universal life index. Hold a key, speak, release. Your thought is transcribed, classified, and stored where omni can index it alongside everything else in your digital life.

## How It Works

```
Hold Cmd+E → speak → release
  → audio.wav saved to recording bucket
  → Whisper transcribes → transcript.json
  → Daemon classifies → classification.json (task, reminder, idea, shopping, etc.)
  → Omni indexes the bucket as source "voice"
  → Searchable alongside files, messages, emails, code, photos
```

## Components

| Component | What | Where |
|-----------|------|-------|
| **Mac app** | PTT recording, Whisper transcription, bucket storage | `eidos-assistant-v0/` |
| **Daemon** | Claude Agent SDK classification (8 categories) | `eidos-assistant-daemon/` |
| **Omni adapter** | Indexes voice buckets as omni resources | `omni-adapter/` |

## Recording Bucket Structure

Each voice recording is a self-contained directory:

```
~/Library/Application Support/eidos-assistant/voice/recordings/{uuid}/
  audio.wav              # raw audio (permanent, source of truth)
  transcript.json        # Whisper output: text, segments, duration, model
  classification.json    # daemon output: category, metadata, confidence
  context.json           # future: screen focus, active app
```

## Categories

The daemon classifies each note into: `reminder`, `task`, `devlog`, `message`, `knowledge`, `idea`, `todo`, `shopping`. These are tags in omni, not destinations.

## Run

```bash
# Build and install the Mac app
cd eidos-assistant-v0
./ci.sh deploy

# Start the daemon (for classification)
cd ../eidos-assistant-daemon
python3 daemon.py
```

**Requirements:** macOS 14+, Python 3.12+, `faster-whisper`, `claude-agent-sdk`

## Omni Integration

The app self-registers with omni on launch by writing a manifest to `~/.config/eidosomni/adapters.d/voice.json`. Omni discovers it automatically. No configuration needed.

## Status

Prototype. Architecture is sound. Core loop needs testing with real microphone input.

## License

MIT
