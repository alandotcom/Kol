#!/bin/bash
# test-transcribe.sh — Launch Kol, trigger a transcription, capture logs
# Usage: ./scripts/test-transcribe.sh [hold_seconds] [app_name]
#   hold_seconds: how long to "record" (default: 3)
#   app_name: app to focus before recording (e.g. "Slack", "Messages", "Cursor")

set -euo pipefail

HOLD=${1:-3}
FOCUS_APP="${2:-}"
APP="/Applications/Kol Debug.app"
SUBSYSTEM="com.alandotcom.Kol"
LOG_FILE="/tmp/kol-transcribe-test.log"

# Right Option key = virtual key code 61
RIGHT_OPT_KEY=61

# --- Preflight ---
if [ ! -d "$APP" ]; then
  echo "ERROR: '$APP' not found. Run: ./scripts/build-install.sh --debug" >&2
  exit 1
fi

# Kill any existing log stream we own
pkill -f "log stream.*${SUBSYSTEM}" 2>/dev/null || true

# --- Launch app (idempotent) ---
echo "Launching Kol Debug..."
open "$APP"
sleep 2  # let it finish launching

# --- Start log capture in background ---
echo "Capturing logs to $LOG_FILE ..."
log stream --predicate "subsystem == '${SUBSYSTEM}'" --level debug --style compact > "$LOG_FILE" 2>&1 &
LOG_PID=$!

# Give log stream a moment to attach
sleep 0.5

# --- Focus target app if specified ---
if [ -n "$FOCUS_APP" ]; then
  echo "Focusing $FOCUS_APP..."
  osascript -e "tell application \"$FOCUS_APP\" to activate"
  sleep 1
fi

# --- Simulate Right Option key press-and-hold via CGEvent (works with global monitors) ---
echo "Pressing Right Option key (start recording)..."
swift -e "
import CoreGraphics
let e = CGEvent(keyboardEventSource: nil, virtualKey: ${RIGHT_OPT_KEY}, keyDown: true)!
e.flags = .maskAlternate
e.post(tap: .cghidEventTap)
"

# Hold for the requested duration (recording silence)
echo "Recording silence for ${HOLD}s..."
sleep "$HOLD"

# --- Release Right Option key (stop recording, triggers transcription) ---
echo "Releasing Right Option key (stop recording)..."
swift -e "
import CoreGraphics
let e = CGEvent(keyboardEventSource: nil, virtualKey: ${RIGHT_OPT_KEY}, keyDown: false)!
e.post(tap: .cghidEventTap)
"

# Wait for transcription pipeline to complete
echo "Waiting for transcription pipeline..."
sleep 8

# --- Stop log capture ---
kill "$LOG_PID" 2>/dev/null || true
wait "$LOG_PID" 2>/dev/null || true

# --- Output ---
LINES=$(wc -l < "$LOG_FILE" | tr -d ' ')
echo ""
echo "=== Captured $LINES log lines ==="
echo "Full log: $LOG_FILE"
echo ""
cat "$LOG_FILE"
