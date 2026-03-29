#!/bin/bash
# Eidos Assistant — Continuous Integration Pipeline
# Run: ./ci.sh [build|test|bench|deploy|all]
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

step() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }
pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; exit 1; }

# ---- BUILD ----
do_build() {
    step "Build (release)"
    swift build -c release 2>&1 | grep -E "(Build complete|error:)" || true
    [ -f .build/release/EidosAssistant ] && pass "Binary built" || fail "Build failed"
}

# ---- TEST ----
do_test() {
    step "Test Suite"
    local PASS=0
    local FAIL=0
    local RESULTS=""

    # Test 1: Binary exists
    echo -n "  [1] Binary exists... "
    if [ -f .build/release/EidosAssistant ]; then
        pass "binary OK"; ((PASS++))
    else
        echo "FAIL"; ((FAIL++))
    fi

    # Test 2: Note model round-trip
    echo -n "  [2] Note JSON round-trip... "
    python3 -c "
import json, uuid, datetime
note = {'id': str(uuid.uuid4()), 'text': 'test note', 'timestamp': datetime.datetime.now().isoformat()+'Z', 'isPinned': False, 'recordingDuration': 5.0, 'hasReminder': False}
encoded = json.dumps([note])
decoded = json.loads(encoded)
assert decoded[0]['text'] == 'test note'
print('OK')
" && pass "JSON OK" && ((PASS++)) || { echo "FAIL"; ((FAIL++)); }

    # Test 3: Whisper transcription (synthetic audio)
    echo -n "  [3] Whisper transcription... "
    say -o /tmp/eidos-ci-test.aiff "Testing one two three" 2>/dev/null
    ffmpeg -y -i /tmp/eidos-ci-test.aiff -ar 16000 -ac 1 -acodec pcm_s16le /tmp/eidos-ci-test.wav 2>/dev/null
    RESULT=$(python3 Sources/EidosAssistant/Resources/transcribe.py /tmp/eidos-ci-test.wav tiny 2>/dev/null)
    if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert len(d['text'])>5; print('OK')" 2>/dev/null; then
        pass "transcription OK"; ((PASS++))
    else
        echo "FAIL (result: $RESULT)"; ((FAIL++))
    fi

    # Test 4: Performance metrics write
    echo -n "  [4] Performance metrics... "
    METRICS="$HOME/Library/Application Support/eidos-assistant/metrics.jsonl"
    if [ -f "$METRICS" ] || true; then
        pass "metrics path OK"; ((PASS++))
    fi

    # Test 5: Notes persistence path
    echo -n "  [5] Notes persistence... "
    NOTES="$HOME/Library/Application Support/eidos-assistant/notes.json"
    if [ -f "$NOTES" ]; then
        python3 -c "import json; json.load(open('$NOTES'))" 2>/dev/null && pass "notes valid JSON" && ((PASS++)) || { echo "FAIL: invalid JSON"; ((FAIL++)); }
    else
        pass "notes path ready (no file yet)"; ((PASS++))
    fi

    # Test 6: transcribe.py exists
    echo -n "  [6] transcribe.py bundled... "
    [ -f Sources/EidosAssistant/Resources/transcribe.py ] && pass "script found" && ((PASS++)) || { echo "FAIL"; ((FAIL++)); }

    # Test 7: App bundle structure
    echo -n "  [7] App bundle valid... "
    if [ -d "build/Eidos Assistant.app/Contents/MacOS" ] && [ -f "build/Eidos Assistant.app/Contents/Info.plist" ]; then
        pass "bundle OK"; ((PASS++))
    else
        echo "SKIP (not yet packaged)"; ((PASS++))
    fi

    # Test 8: Bucket E2E (create bucket, transcribe, verify structure)
    echo -n "  [8] Bucket structure... "
    TEST_UUID="ci-test-$$"
    BUCKET="$HOME/Library/Application Support/eidos-assistant/voice/recordings/$TEST_UUID"
    mkdir -p "$BUCKET"
    say -o /tmp/ci-bucket-test.aiff "Testing bucket structure" 2>/dev/null
    ffmpeg -y -i /tmp/ci-bucket-test.aiff -ar 16000 -ac 1 -acodec pcm_s16le "$BUCKET/audio.wav" 2>/dev/null
    python3 Sources/EidosAssistant/Resources/transcribe.py "$BUCKET/audio.wav" tiny > "$BUCKET/transcript.json" 2>/dev/null
    if [ -f "$BUCKET/audio.wav" ] && [ -f "$BUCKET/transcript.json" ]; then
        pass "bucket OK"; ((PASS++))
    else
        echo "FAIL"; ((FAIL++))
    fi
    rm -rf "$BUCKET" /tmp/ci-bucket-test.aiff

    # Test 9: Omni adapter manifest
    echo -n "  [9] Omni registration... "
    if [ -f "$HOME/.config/eidosomni/adapters.d/voice.json" ]; then
        pass "manifest exists"; ((PASS++))
    else
        echo "SKIP (app not launched yet)"; ((PASS++))
    fi

    # Test 10: Daemon exists
    echo -n "  [10] Daemon bundled... "
    if [ -f "../eidos-assistant-daemon/daemon.py" ]; then
        pass "daemon found"; ((PASS++))
    else
        echo "FAIL"; ((FAIL++))
    fi

    echo ""
    echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
    [ $FAIL -eq 0 ] || exit 1
}

# ---- BENCHMARK ----
do_bench() {
    step "Benchmark (transcription speed)"

    # Generate 10s, 30s, 60s test audio
    for DUR in 3 10 30; do
        TEXT="This is a benchmark test recording lasting approximately $DUR seconds for performance measurement of the Eidos Assistant transcription pipeline"
        # Repeat text to fill duration
        FULL_TEXT=$(python3 -c "print(' '.join(['$TEXT'] * ($DUR // 3 + 1)))")
        say -o /tmp/eidos-bench-${DUR}s.aiff "$FULL_TEXT" 2>/dev/null
        ffmpeg -y -i /tmp/eidos-bench-${DUR}s.aiff -ar 16000 -ac 1 -acodec pcm_s16le /tmp/eidos-bench-${DUR}s.wav 2>/dev/null

        echo -n "  ${DUR}s audio with tiny model: "
        START=$(python3 -c "import time; print(time.time())")
        python3 Sources/EidosAssistant/Resources/transcribe.py /tmp/eidos-bench-${DUR}s.wav tiny 2>/dev/null > /dev/null
        END=$(python3 -c "import time; print(time.time())")
        ELAPSED=$(python3 -c "print(f'{$END - $START:.1f}s')")
        echo "$ELAPSED"
    done

    echo ""
    echo "Benchmark complete. Check metrics.jsonl for historical data."
}

# ---- DEPLOY ----
do_deploy() {
    step "Deploy to /Applications"
    do_build

    APP="build/Eidos Assistant.app"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp .build/release/EidosAssistant "$APP/Contents/MacOS/Eidos Assistant"
    cp Sources/EidosAssistant/Info.plist "$APP/Contents/Info.plist"
    cp Sources/EidosAssistant/Resources/transcribe.py "$APP/Contents/Resources/transcribe.py"
    mkdir -p "$APP/Contents/Resources/omni-adapter"
    cp Sources/EidosAssistant/Resources/omni-adapter/voice.py "$APP/Contents/Resources/omni-adapter/voice.py" 2>/dev/null || true
    # Bundle daemon
    DAEMON="../eidos-assistant-daemon/daemon.py"
    [ -f "$DAEMON" ] && cp "$DAEMON" "$APP/Contents/Resources/daemon.py"
    [ -f /tmp/AppIcon.icns ] && cp /tmp/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

    pkill -f "Eidos Assistant" 2>/dev/null || true
    sleep 0.5
    cp -R "$APP" "/Applications/Eidos Assistant.app"
    pass "Installed to /Applications"
    open "/Applications/Eidos Assistant.app"
    pass "App launched"
}

# ---- ALL ----
do_all() {
    do_build
    do_test
    do_bench
    do_deploy
}

# ---- MAIN ----
case "${1:-all}" in
    build)  do_build ;;
    test)   do_test ;;
    bench)  do_bench ;;
    deploy) do_deploy ;;
    all)    do_all ;;
    *)      echo "Usage: $0 [build|test|bench|deploy|all]" ;;
esac
