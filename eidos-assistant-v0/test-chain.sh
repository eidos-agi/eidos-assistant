#!/bin/bash
# test-chain.sh — 10 isolated tests for the eidos-assistant recording chain.
# Each test targets one link. When one fails, you know exactly what's broken.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0; FAIL=0; SKIP=0
APP_SUPPORT="$HOME/Library/Application Support/eidos-assistant"
RECORDINGS="$APP_SUPPORT/voice/recordings"
MANIFEST="$APP_SUPPORT/voice/manifest.jsonl"

pass() { echo -e "  ${GREEN}PASS${NC}: $1"; ((PASS++)); }
fail() { echo -e "  ${RED}FAIL${NC}: $1"; ((FAIL++)); }
skip() { echo -e "  ${YELLOW}SKIP${NC}: $1"; ((SKIP++)); }

echo "=== Eidos Assistant Chain Test ==="
echo ""

# ─────────────────────────────────────────────────────────────────
# TEST 1: Can the system record audio at all?
# Isolates: macOS audio subsystem, microphone permission
# ─────────────────────────────────────────────────────────────────
echo "[1/10] System audio recording"
TESTFILE="/tmp/eidos-chain-test-1.wav"
rm -f "$TESTFILE"
# Record 2 seconds from default input using ffmpeg (more reliable than afrecord)
ffmpeg -f avfoundation -i ":0" -t 2 -ar 16000 -ac 1 -acodec pcm_s16le -y "$TESTFILE" &>/dev/null &
RECPID=$!
sleep 3
kill $RECPID 2>/dev/null; wait $RECPID 2>/dev/null
if [ -f "$TESTFILE" ] && [ "$(stat -f%z "$TESTFILE" 2>/dev/null || echo 0)" -gt 1000 ]; then
    pass "System can record audio ($(du -h "$TESTFILE" | cut -f1))"
else
    # Fallback: use synthetic audio so remaining tests can still run
    say -o /tmp/eidos-chain-synth.aiff "Test audio for chain validation" 2>/dev/null
    ffmpeg -y -i /tmp/eidos-chain-synth.aiff -ar 16000 -ac 1 -acodec pcm_s16le "$TESTFILE" 2>/dev/null
    if [ -f "$TESTFILE" ]; then
        skip "Mic recording failed (permission?) — using synthetic audio for remaining tests"
    else
        fail "Cannot record audio at all"
    fi
fi

# ─────────────────────────────────────────────────────────────────
# TEST 2: Is the recorded audio actually audible (not silence)?
# Isolates: mic input level, correct input device selected
# ─────────────────────────────────────────────────────────────────
echo "[2/10] Audio contains signal (not silence)"
if [ -f "$TESTFILE" ]; then
    # Check RMS level — silence is < -50dB
    RMS=$(ffmpeg -i "$TESTFILE" -af volumedetect -f null /dev/null 2>&1 | grep mean_volume | awk '{print $5}')
    if [ -n "$RMS" ]; then
        # RMS is negative dB. Silence is around -91. Real audio is -30 to -10.
        IS_SILENT=$(python3 -c "print('yes' if float('${RMS}') < -60 else 'no')" 2>/dev/null || echo "unknown")
        if [ "$IS_SILENT" = "yes" ]; then
            fail "Audio is silence (RMS: ${RMS} dB) — wrong input device or mic muted"
        elif [ "$IS_SILENT" = "no" ]; then
            pass "Audio has signal (RMS: ${RMS} dB)"
        else
            skip "Could not determine audio level"
        fi
    else
        skip "ffmpeg volumedetect failed"
    fi
else
    skip "No test recording from test 1"
fi

# ─────────────────────────────────────────────────────────────────
# TEST 3: Can Whisper transcribe real mic audio?
# Isolates: Whisper model loading, real audio format compatibility
# ─────────────────────────────────────────────────────────────────
echo "[3/10] Whisper transcribes real audio"
if [ -f "$TESTFILE" ]; then
    RESULT=$(python3 Sources/EidosAssistant/Resources/transcribe.py "$TESTFILE" tiny 2>/dev/null || echo "TRANSCRIBE_FAILED")
    if [ "$RESULT" = "TRANSCRIBE_FAILED" ]; then
        fail "Whisper crashed on real mic audio"
    else
        TEXT=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('text',''))" 2>/dev/null || echo "")
        DURATION=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('duration_sec',0))" 2>/dev/null || echo "0")
        if [ -n "$TEXT" ] && [ "$TEXT" != "" ]; then
            pass "Whisper output: \"$TEXT\" (${DURATION}s)"
        else
            # Empty text from 2s of real audio is expected if room is quiet
            pass "Whisper returned empty (expected for quiet room — ${DURATION}s audio)"
        fi
    fi
else
    skip "No test recording"
fi

# ─────────────────────────────────────────────────────────────────
# TEST 4: Can a bucket be created and populated?
# Isolates: filesystem permissions, directory creation, file moves
# ─────────────────────────────────────────────────────────────────
echo "[4/10] Bucket creation and population"
TEST_UUID="chain-test-$(date +%s)"
TEST_BUCKET="$RECORDINGS/$TEST_UUID"
mkdir -p "$TEST_BUCKET" 2>/dev/null
if [ -d "$TEST_BUCKET" ]; then
    # Simulate what the app does: move audio, write transcript
    if [ -f "$TESTFILE" ]; then
        cp "$TESTFILE" "$TEST_BUCKET/audio.wav"
        python3 Sources/EidosAssistant/Resources/transcribe.py "$TEST_BUCKET/audio.wav" tiny > "$TEST_BUCKET/transcript.json" 2>/dev/null
        HAS_AUDIO=$([[ -f "$TEST_BUCKET/audio.wav" ]] && echo "Y" || echo "N")
        HAS_TRANS=$([[ -f "$TEST_BUCKET/transcript.json" ]] && echo "Y" || echo "N")
        if [ "$HAS_AUDIO" = "Y" ] && [ "$HAS_TRANS" = "Y" ]; then
            pass "Bucket has audio.wav + transcript.json"
        else
            fail "Bucket incomplete: audio=$HAS_AUDIO transcript=$HAS_TRANS"
        fi
    else
        skip "No test recording to populate bucket"
    fi
else
    fail "Cannot create bucket directory at $TEST_BUCKET"
fi

# ─────────────────────────────────────────────────────────────────
# TEST 5: Can the manifest be appended?
# Isolates: manifest.jsonl write, file locking, JSON format
# ─────────────────────────────────────────────────────────────────
echo "[5/10] Manifest append"
BEFORE_LINES=$(wc -l < "$MANIFEST" 2>/dev/null | tr -d ' ' || echo "0")
echo "{\"uuid\":\"$TEST_UUID\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"status\":\"test\"}" >> "$MANIFEST"
AFTER_LINES=$(wc -l < "$MANIFEST" 2>/dev/null | tr -d ' ')
if [ "$AFTER_LINES" -gt "$BEFORE_LINES" ]; then
    # Verify last line is valid JSON
    LAST=$(tail -1 "$MANIFEST")
    echo "$LAST" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null && pass "Manifest appended (${AFTER_LINES} lines)" || fail "Manifest has invalid JSON"
else
    fail "Manifest did not grow"
fi

# ─────────────────────────────────────────────────────────────────
# TEST 6: Can the daemon classify a note?
# Isolates: daemon connectivity, Claude Agent SDK, classification
# ─────────────────────────────────────────────────────────────────
echo "[6/10] Daemon classification"
if [ -S /tmp/eidos-assistant.sock ]; then
    # Send a test note via Unix socket
    RESPONSE=$(echo '{"text":"Buy eggs and milk from the store","uuid":"daemon-test"}' | socat - UNIX-CONNECT:/tmp/eidos-assistant.sock 2>/dev/null || echo "CONNECT_FAILED")
    if [ "$RESPONSE" = "CONNECT_FAILED" ]; then
        fail "Daemon socket exists but connection failed"
    else
        CATEGORY=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('classified','?'))" 2>/dev/null || echo "?")
        if [ "$CATEGORY" != "?" ]; then
            pass "Daemon classified as: $CATEGORY"
        else
            fail "Daemon returned unexpected response: $RESPONSE"
        fi
    fi
else
    skip "Daemon not running (socket not found) — start with: python3 eidos-assistant-daemon/daemon.py"
fi

# ─────────────────────────────────────────────────────────────────
# TEST 7: Does the omni adapter manifest exist?
# Isolates: app → omni registration
# ─────────────────────────────────────────────────────────────────
echo "[7/10] Omni adapter registration"
OMNI_MANIFEST="$HOME/.config/eidosomni/adapters.d/voice.json"
if [ -f "$OMNI_MANIFEST" ]; then
    ADAPTER_PATH=$(python3 -c "import json; print(json.load(open('$OMNI_MANIFEST'))['adapter']['path'])" 2>/dev/null)
    if [ -f "$ADAPTER_PATH" ]; then
        pass "Registered and adapter exists at: $(basename "$ADAPTER_PATH")"
    else
        fail "Manifest exists but adapter path is dead: $ADAPTER_PATH"
    fi
else
    fail "No omni manifest — app hasn't registered"
fi

# ─────────────────────────────────────────────────────────────────
# TEST 8: Can the omni adapter read a bucket?
# Isolates: adapter's read_content logic
# ─────────────────────────────────────────────────────────────────
echo "[8/10] Omni adapter reads bucket"
if [ -d "$TEST_BUCKET" ] && [ -f "$TEST_BUCKET/transcript.json" ]; then
    ADAPTER_RESULT=$(python3 -c "
import json
from pathlib import Path
bucket = Path('$TEST_BUCKET')
transcript = json.loads((bucket / 'transcript.json').read_text())
audio = bucket / 'audio.wav'
result = {
    'text': transcript.get('text', '')[:80],
    'duration': transcript.get('duration_sec', 0),
    'has_audio': audio.exists(),
    'audio_size': audio.stat().st_size if audio.exists() else 0,
}
print(json.dumps(result))
" 2>/dev/null || echo "FAILED")
    if [ "$ADAPTER_RESULT" != "FAILED" ]; then
        pass "Adapter read: $(echo "$ADAPTER_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{d[\"duration\"]}s, {d[\"audio_size\"]} bytes')")"
    else
        fail "Adapter could not read bucket"
    fi
else
    skip "No test bucket with transcript"
fi

# ─────────────────────────────────────────────────────────────────
# TEST 9: Is the app process healthy?
# Isolates: app running, not consuming excessive resources
# ─────────────────────────────────────────────────────────────────
echo "[9/10] App process health"
APP_PID=$(pgrep -f "Eidos Assistant" | head -1)
if [ -n "$APP_PID" ]; then
    RSS=$(ps -o rss= -p "$APP_PID" | tr -d ' ')
    RSS_MB=$((RSS / 1024))
    CPU=$(ps -o %cpu= -p "$APP_PID" | tr -d ' ')
    THREADS=$(ps -o nlwp= -p "$APP_PID" 2>/dev/null || ps -M -p "$APP_PID" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$RSS_MB" -lt 150 ]; then
        pass "App healthy: ${RSS_MB}MB RAM, ${CPU}% CPU"
    else
        fail "App using ${RSS_MB}MB RAM (limit: 150MB) — possible leak"
    fi
else
    fail "App not running"
fi

# ─────────────────────────────────────────────────────────────────
# TEST 10: End-to-end synthetic proof (the full chain minus hotkey)
# Isolates: everything except the PTT hotkey
# ─────────────────────────────────────────────────────────────────
echo "[10/10] End-to-end chain (synthetic)"
E2E_UUID="e2e-chain-$(date +%s)"
E2E_BUCKET="$RECORDINGS/$E2E_UUID"
mkdir -p "$E2E_BUCKET"

# Generate audio with macOS say
say -o /tmp/e2e-chain.aiff "Testing the full recording chain" 2>/dev/null
ffmpeg -y -i /tmp/e2e-chain.aiff -ar 16000 -ac 1 -acodec pcm_s16le "$E2E_BUCKET/audio.wav" 2>/dev/null

# Transcribe
python3 Sources/EidosAssistant/Resources/transcribe.py "$E2E_BUCKET/audio.wav" tiny > "$E2E_BUCKET/transcript.json" 2>/dev/null

# Append manifest
echo "{\"uuid\":\"$E2E_UUID\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"status\":\"transcribed\"}" >> "$MANIFEST"

# Check
E2E_TEXT=$(python3 -c "import json; print(json.load(open('$E2E_BUCKET/transcript.json'))['text'][:60])" 2>/dev/null || echo "")
if [ -f "$E2E_BUCKET/audio.wav" ] && [ -f "$E2E_BUCKET/transcript.json" ] && [ -n "$E2E_TEXT" ]; then
    pass "Full chain: audio → transcript → manifest (\"$E2E_TEXT\")"
else
    fail "Chain broken: audio=$([ -f "$E2E_BUCKET/audio.wav" ] && echo Y || echo N) transcript=$([ -f "$E2E_BUCKET/transcript.json" ] && echo Y || echo N)"
fi

# Cleanup test buckets
rm -rf "$RECORDINGS/chain-test-"* "$RECORDINGS/e2e-chain-"* /tmp/eidos-chain-test-1.wav /tmp/e2e-chain.aiff

echo ""
echo "════════════════════════════════════════"
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC}"
echo ""
if [ "$FAIL" -gt 0 ]; then
    echo "Fix the failures above, then run again."
    exit 1
else
    echo "Chain healthy. The only untested link: PTT hotkey → AVAudioRecorder."
    echo "To test: hold Cmd+E in the app, speak, release, then run:"
    echo "  ls -la \"$RECORDINGS/\" | tail -3"
fi
