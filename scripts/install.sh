#!/usr/bin/env bash
# install.sh — install the virtual audio driver
# Called by: yournoisecli setup  (with sudo)
# Usage: sudo ./scripts/install.sh [--driver-path /path/to/YourAppMicrophone.driver]
set -euo pipefail
 
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/config/driver.env"
 
HAL_DIR="/Library/Audio/Plug-Ins/HAL"
INSTALL_DEST="$HAL_DIR/$DRIVER_BUNDLE_NAME"
 
# Allow overriding the driver source path (useful when called from CLI binary)
DRIVER_SRC="${1:-$REPO_ROOT/dist/$DRIVER_BUNDLE_NAME}"
[[ "${1:-}" == "--driver-path" ]] && DRIVER_SRC="${2:-}"
 
# ── Preflight ────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
  echo "✖ This script must be run as root (use sudo)"
  exit 1
fi
 
if [[ ! -d "$DRIVER_SRC" ]]; then
  echo "✖ Driver bundle not found at: $DRIVER_SRC"
  echo "  Run ./scripts/build.sh first"
  exit 1
fi
 
# ── Verify signature before installing ───────────────────────────
echo "▶ Verifying driver signature..."
if ! codesign --verify --deep --strict "$DRIVER_SRC" 2>/dev/null; then
  echo "  ⚠ Driver is not signed — installing anyway (dev mode)"
  echo "    Gatekeeper will block this on end-user machines"
fi
 
# ── Remove existing version if present ──────────────────────────
if [[ -d "$INSTALL_DEST" ]]; then
  echo "▶ Removing existing driver..."
  rm -rf "$INSTALL_DEST"
fi
 
# ── Install ──────────────────────────────────────────────────────
echo "▶ Installing $DRIVER_BUNDLE_NAME..."
cp -r "$DRIVER_SRC" "$INSTALL_DEST"
chown -R root:wheel "$INSTALL_DEST"
chmod -R 755 "$INSTALL_DEST"
echo "  Installed → $INSTALL_DEST"
 
# ── Restart coreaudiod ───────────────────────────────────────────
echo "▶ Restarting coreaudiod..."
killall coreaudiod 2>/dev/null || true
sleep 1   # give it a moment to restart
 
# ── Verify the device is now visible ────────────────────────────
echo "▶ Verifying device visibility..."
FOUND=$(system_profiler SPAudioDataType 2>/dev/null | grep "$DEVICE_NAME" || true)
if [[ -n "$FOUND" ]]; then
  echo "  ✔ \"$DEVICE_NAME\" is visible to the OS"
else
  echo "  ⚠ Device not yet visible — try opening Audio MIDI Setup to confirm"
  echo "    (system_profiler can lag a few seconds after coreaudiod restart)"
fi
 
echo ""
echo "✔ Installation complete."
echo "  Select \"$DEVICE_NAME\" as your microphone in any app."