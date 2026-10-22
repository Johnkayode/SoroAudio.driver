#!/usr/bin/env bash

set -euo pipefail
 
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/config/driver.env"
 
HAL_DIR="/Library/Audio/Plug-Ins/HAL"
INSTALL_DEST="$HAL_DIR/$DRIVER_BUNDLE_NAME"
 
if [[ "$EUID" -ne 0 ]]; then
  echo "✖ This script must be run as root (use sudo)"
  exit 1
fi
 
if [[ ! -d "$INSTALL_DEST" ]]; then
  echo "  Nothing to remove — $DRIVER_BUNDLE_NAME is not installed"
  exit 0
fi
 
echo "▶ Removing $DRIVER_BUNDLE_NAME..."
rm -rf "$INSTALL_DEST"
 
echo "▶ Restarting coreaudiod..."
killall coreaudiod 2>/dev/null || true
 
echo "✔ Uninstalled."
 
