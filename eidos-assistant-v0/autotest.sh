#!/bin/bash
# Eidos Assistant — Autonomous Test & Improvement Loop
# Runs without human intervention. Generates test audio, transcribes,
# benchmarks, detects regressions, and logs improvement opportunities.
#
# Usage:
#   ./autotest.sh              # Run once
#   ./autotest.sh --watch      # Run every 5 minutes (background daemon)
#   ./autotest.sh --report     # Show improvement report
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

APP_SUPPORT="$HOME/Library/Application Support/eidos-assistant"
METRICS="$APP_SUPPORT/metrics.jsonl"
AUTOTEST_LOG="$APP_SUPPORT/autotest.jsonl"
IMPROVEMENTS="$APP_SUPPORT/improvements.md"

mkdir -p "$APP_SUPPORT"

# ---- Test Corpus: diverse audio samples ----
declare -a TEST_CASES=(
    "short|Hello world|2"
    "medium|This is a medium length test sentence for the Eidos Assistant transcription engine to process|5"
    "long|Meeting notes for March twenty ninth. First, we discussed the product roadmap for Q2. The engineering team will focus on performance optimization and reducing transcription latency. Second, the design team presented new mockups for the settings panel. Third, we agreed to ship version one by end of month. Action items: Daniel to set up CI CD pipeline. Review pull requests by Friday. Schedule a demo for stakeholders next Tuesday|20"
    "technical|The API endpoint returns a JSON response with status code 200. The payload includes an array of transcription objects each containing a text field and a confidence score between zero and one|10"
    "numbers|My phone number is 555 123 4567. The meeting is at 3 30 PM on March 29th 2026. The budget is one hundred fifty thousand dollars|8"
    "names|Please tell Sarah and Michael that the Kubernetes deployment on AWS us east one is ready for review|6"
    "whisper|Remind me to check the Whisper model accuracy after upgrading to faster whisper with C translate 2 backend|7"
    "quiet|yes|1"
)

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log_result() {
    local name="$1" model="$2" expected_words="$3" actual_words="$4" time_sec="$5" accuracy="$6"
    echo "{\"timestamp\":\"$(timestamp)\",\"test\":\"$name\",\"model\":\"$model\",\"expected_words\":$expected_words,\"actual_words\":$actual_words,\"time_sec\":$time_sec,\"accuracy\":$accuracy}" >> "$AUTOTEST_LOG"
}

# ---- Run One Test ----
run_test() {
    local name="$1" text="$2" expected_dur="$3" model="${4:-tiny}"

    # Generate audio
    say -o "/tmp/eidos-auto-${name}.aiff" "$text" 2>/dev/null
    ffmpeg -y -i "/tmp/eidos-auto-${name}.aiff" -ar 16000 -ac 1 -acodec pcm_s16le "/tmp/eidos-auto-${name}.wav" 2>/dev/null

    # Transcribe and time it
    local START=$(python3 -c "import time; print(time.time())")
    local RESULT=$(python3 Sources/EidosAssistant/Resources/transcribe.py "/tmp/eidos-auto-${name}.wav" "$model" 2>/dev/null)
    local END=$(python3 -c "import time; print(time.time())")
    local ELAPSED=$(python3 -c "print(f'{$END - $START:.2f}')")

    # Parse result
    local TRANSCRIBED=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('text',''))" 2>/dev/null || echo "")
    local ACTUAL_WORDS=$(echo "$TRANSCRIBED" | wc -w | tr -d ' ')
    local EXPECTED_WORDS=$(echo "$text" | wc -w | tr -d ' ')

    # Accuracy: word-level similarity (simple Jaccard)
    local ACCURACY=$(python3 -c "
ref = set('$text'.lower().split())
hyp = set('''$TRANSCRIBED'''.lower().split())
if len(ref) == 0: print(0)
else: print(f'{len(ref & hyp) / len(ref | hyp):.2f}')
" 2>/dev/null || echo "0")

    echo "  [$name] ${ELAPSED}s | ${ACTUAL_WORDS}/${EXPECTED_WORDS} words | accuracy: ${ACCURACY} | model: $model"
    log_result "$name" "$model" "$EXPECTED_WORDS" "$ACTUAL_WORDS" "$ELAPSED" "$ACCURACY"

    # Cleanup
    rm -f "/tmp/eidos-auto-${name}.aiff" "/tmp/eidos-auto-${name}.wav"
}

# ---- Detect Regressions ----
detect_regressions() {
    python3 << 'PYEOF'
import json, sys
from collections import defaultdict

log_path = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    with open(log_path) as f:
        entries = [json.loads(line) for line in f if line.strip()]
except:
    print("  No historical data yet")
    sys.exit(0)

# Group by test name, get last 5 runs
by_test = defaultdict(list)
for e in entries:
    by_test[e["test"]].append(e)

regressions = []
for name, runs in by_test.items():
    recent = runs[-5:]
    if len(recent) < 2:
        continue
    # Check if latest is >50% slower than average of previous
    prev_avg = sum(r["time_sec"] for r in recent[:-1]) / len(recent[:-1])
    latest = recent[-1]["time_sec"]
    if latest > prev_avg * 1.5 and prev_avg > 0:
        regressions.append(f"  REGRESSION: {name} — {latest:.1f}s vs avg {prev_avg:.1f}s (+{(latest/prev_avg - 1)*100:.0f}%)")
    # Check accuracy drop
    prev_acc = sum(float(r["accuracy"]) for r in recent[:-1]) / len(recent[:-1])
    latest_acc = float(recent[-1]["accuracy"])
    if latest_acc < prev_acc - 0.1:
        regressions.append(f"  REGRESSION: {name} accuracy — {latest_acc:.2f} vs avg {prev_acc:.2f}")

if regressions:
    print("\n".join(regressions))
else:
    print("  No regressions detected")
PYEOF
}

# ---- Generate Improvement Report ----
generate_report() {
    export AUTOTEST_LOG_EXPORT="$AUTOTEST_LOG"
    python3 << 'PYEOF' > "$IMPROVEMENTS"
import json, sys
from collections import defaultdict
from datetime import datetime

import os
log_path = os.environ.get("AUTOTEST_LOG_EXPORT", "")
try:
    with open(log_path) as f:
        entries = [json.loads(line) for line in f if line.strip()]
except:
    print("# Eidos Assistant — Improvement Report\n\nNo data yet. Run `./autotest.sh` first.")
    sys.exit(0)

print("# Eidos Assistant — Improvement Report")
print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")

# Summary stats
by_model = defaultdict(list)
for e in entries:
    by_model[e["model"]].append(e)

print("## Model Performance\n")
print("| Model | Runs | Avg Time | Avg Accuracy |")
print("|-------|------|----------|--------------|")
for model, runs in sorted(by_model.items()):
    avg_time = sum(r["time_sec"] for r in runs) / len(runs)
    avg_acc = sum(float(r["accuracy"]) for r in runs) / len(runs)
    print(f"| {model} | {len(runs)} | {avg_time:.1f}s | {avg_acc:.0%} |")

# Per-test breakdown
print("\n## Per-Test Breakdown\n")
by_test = defaultdict(list)
for e in entries:
    by_test[e["test"]].append(e)

for name, runs in sorted(by_test.items()):
    latest = runs[-1]
    trend = "stable"
    if len(runs) >= 3:
        times = [r["time_sec"] for r in runs[-3:]]
        if times[-1] > times[0] * 1.3:
            trend = "SLOWING"
        elif times[-1] < times[0] * 0.7:
            trend = "improving"
    print(f"- **{name}**: {latest['time_sec']:.1f}s, accuracy {float(latest['accuracy']):.0%} ({trend})")

# Improvement suggestions
print("\n## Suggested Improvements\n")
slowest = max(entries, key=lambda e: e["time_sec"])
print(f"- Slowest test: **{slowest['test']}** at {slowest['time_sec']:.1f}s — consider chunking long audio")
lowest_acc = min(entries, key=lambda e: float(e["accuracy"]))
print(f"- Lowest accuracy: **{lowest_acc['test']}** at {float(lowest_acc['accuracy']):.0%} — may need prompt tuning")

avg_all = sum(e["time_sec"] for e in entries) / len(entries)
if avg_all > 5:
    print(f"- Average transcription time is {avg_all:.1f}s — consider 'tiny' model for short notes")
PYEOF

    echo "  Report written to: $IMPROVEMENTS"
    cat "$IMPROVEMENTS"
}

# ---- Main ----
case "${1:---once}" in
    --once|-o)
        echo "=== Eidos Assistant Autotest — $(date) ==="
        echo ""
        echo "Running test corpus (tiny model for speed)..."
        for tc in "${TEST_CASES[@]}"; do
            IFS='|' read -r name text dur <<< "$tc"
            run_test "$name" "$text" "$dur" "tiny"
        done
        echo ""
        echo "Checking for regressions..."
        detect_regressions "$AUTOTEST_LOG"
        echo ""
        echo "Generating improvement report..."
        generate_report
        ;;

    --watch|-w)
        echo "Starting autotest daemon (runs every 5 minutes)..."
        echo "PID: $$"
        echo $$ > "$APP_SUPPORT/autotest.pid"
        while true; do
            echo "[$(date)] Running autotest cycle..."
            "$0" --once > "$APP_SUPPORT/autotest-latest.log" 2>&1
            echo "[$(date)] Cycle complete. Sleeping 5 minutes..."
            sleep 300
        done
        ;;

    --report|-r)
        if [ -f "$IMPROVEMENTS" ]; then
            cat "$IMPROVEMENTS"
        else
            echo "No report yet. Run ./autotest.sh first."
        fi
        ;;

    --stop|-s)
        if [ -f "$APP_SUPPORT/autotest.pid" ]; then
            kill $(cat "$APP_SUPPORT/autotest.pid") 2>/dev/null && echo "Daemon stopped" || echo "Daemon not running"
            rm -f "$APP_SUPPORT/autotest.pid"
        else
            echo "No daemon running"
        fi
        ;;

    *)
        echo "Usage: $0 [--once|--watch|--report|--stop]"
        ;;
esac
