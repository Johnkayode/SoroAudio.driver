#!/usr/bin/env bash
# test.sh — verify the driver is installed and audio flows through it
# Usage: ./scripts/test.sh
# Requires: sox  (brew install sox)
set -euo pipefail
 
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/config/driver.env"
 
PASS=0
FAIL=0
WARN=0
 
ok()   { echo "  ✔ $*"; ((PASS++)); }
fail() { echo "  ✖ $*"; ((FAIL++)); }
warn() { echo "  ⚠ $*"; ((WARN++)); }
section() { echo ""; echo "── $* ──────────────────────────────────────────"; }
 
# ── 1. Driver bundle on disk ─────────────────────────────────────
section "Driver installation"
INSTALL_DEST="/Library/Audio/Plug-Ins/HAL/$DRIVER_BUNDLE_NAME"
 
if [[ -d "$INSTALL_DEST" ]]; then
  ok "Driver bundle found at $INSTALL_DEST"
else
  fail "Driver not installed — run: sudo ./scripts/install.sh"
fi
 
# ── 2. Code signature ────────────────────────────────────────────
section "Code signature"
if codesign --verify --deep --strict "$INSTALL_DEST" 2>/dev/null; then
  SIGNER=$(codesign -dv "$INSTALL_DEST" 2>&1 | grep "Authority=" | head -1 | cut -d= -f2)
  ok "Valid signature: $SIGNER"
else
  warn "Driver is unsigned — OK for local dev, not for distribution"
fi
 
# ── 3. OS audio visibility ───────────────────────────────────────
section "OS audio visibility"
if system_profiler SPAudioDataType 2>/dev/null | grep -q "$DEVICE_NAME"; then
  ok "\"$DEVICE_NAME\" visible via system_profiler"
else
  fail "\"$DEVICE_NAME\" NOT visible — try: sudo killall coreaudiod"
fi
 
# Check via pluginkit
if pluginkit -m -p com.apple.CoreAudio.HALPlugin 2>/dev/null | grep -q "$BUNDLE_ID"; then
  ok "Bundle ID $BUNDLE_ID registered with pluginkit"
else
  warn "Bundle not found via pluginkit (may just be a caching delay)"
fi
 
# ── 4. Audio round-trip (requires sox) ──────────────────────────
section "Audio round-trip"
if ! command -v sox &>/dev/null; then
  warn "sox not installed — skipping audio round-trip test"
  echo "     Install with: brew install sox"
else
  TONE_FILE="/tmp/nc_driver_test_tone.wav"
  CAPTURE_FILE="/tmp/nc_driver_test_capture.wav"
 
  echo "  Generating 2s 440Hz test tone → playing into default output..."
  sox -n -r "$SAMPLE_RATE" -c "$CHANNELS" "$TONE_FILE" synth 2 sine 440 vol 0.5
 
  echo "  Recording 2s from \"$DEVICE_NAME\"..."
  # Play the tone in background, simultaneously record from the virtual mic
  # This tests the full loop: default out → (your CLI NC engine) → virtual mic
  sox "$TONE_FILE" -t coreaudio default &
  PLAY_PID=$!
  sox -t coreaudio "$DEVICE_NAME" -r "$SAMPLE_RATE" -c "$CHANNELS" "$CAPTURE_FILE" trim 0 2 2>/dev/null || true
  wait $PLAY_PID 2>/dev/null || true
 
  if [[ -f "$CAPTURE_FILE" ]]; then
    DURATION=$(soxi -D "$CAPTURE_FILE" 2>/dev/null || echo "0")
    if (( $(echo "$DURATION > 1.0" | bc -l) )); then
      ok "Captured ${DURATION}s of audio from \"$DEVICE_NAME\""
      echo "     Listen: open $CAPTURE_FILE"
    else
      fail "Capture too short (${DURATION}s) — device may not be receiving audio"
    fi
  else
    fail "No audio captured from \"$DEVICE_NAME\""
  fi
 
  rm -f "$TONE_FILE"
fi
 
# ── 5. coreaudiod log check ──────────────────────────────────────
section "coreaudiod errors (last 60s)"
ERRORS=$(log show \
  --predicate 'process == "coreaudiod" && messageType == "error"' \
  --last 60s 2>/dev/null \
  | grep -i "$BUNDLE_ID\|$DEVICE_NAME" || true)
 
if [[ -z "$ERRORS" ]]; then
  ok "No coreaudiod errors related to your driver"
else
  fail "coreaudiod errors found:"
  echo "$ERRORS" | head -10 | sed 's/^/     /'
fi
 
# ── Summary ──────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────"
echo "  Results: $PASS passed  $WARN warnings  $FAIL failed"
echo "────────────────────────────────────────────────"
 
if [[ "$FAIL" -gt 0 ]]; then
  echo ""
  echo "  Debug tip: stream coreaudiod live with:"
  echo "  log stream --predicate 'process == \"coreaudiod\"' --level debug"
  exit 1
fi