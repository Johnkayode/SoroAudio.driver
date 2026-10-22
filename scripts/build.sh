#!/usr/bin/env bash
# build.sh — compile, sign, and notarize the virtual audio driver
# Usage: ./scripts/build.sh [--skip-notarize]
set -euo pipefail
 
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/config/driver.env"
source "$REPO_ROOT/config/credentials.env"
 
SKIP_NOTARIZE=false
[[ "${1:-}" == "--skip-notarize" ]] && SKIP_NOTARIZE=true

BH_PROJECT="$REPO_ROOT/external/blackhole.git/BlackHole.xcodeproj"
DERIVED_DATA="$REPO_ROOT/dist/build"
PRODUCTS="$DERIVED_DATA/Build/Products/Release"
DRIVER_OUT="$REPO_ROOT/dist/$DRIVER_BUNDLE_NAME"
ZIP_OUT="$REPO_ROOT/dist/driver-notarize.zip"
 
# ── Preflight ────────────────────────────────────────────────────
echo "▶ Checking prerequisites..."
 
if [[ ! -d "$REPO_ROOT/external/blackhole.git" ]]; then
  echo "✖ BlackHole submodule not found."
  echo "  Run: git submodule add https://github.com/ExistentialAudio/BlackHole external/blackhole"
  exit 1
fi
 
if ! xcode-select -p &>/dev/null; then
  echo "✖ Xcode command line tools not installed. Run: xcode-select --install"
  exit 1
fi
 
# ── Build ────────────────────────────────────────────────────────
echo "▶ Building $DRIVER_BUNDLE_NAME..."
rm -rf "$DERIVED_DATA"

# GCC_PREPROCESSOR_DEFINITIONS splits on spaces, so values like "Soro Microphone"
# get split into separate tokens and the compilation fails. Instead we use a
# prefix header that the compiler forces before any source file. BlackHole.c
# guards all constants with #ifndef so they pick up our overrides cleanly.
PREFIX_HEADER="$DERIVED_DATA/soro_prefix.h"
mkdir -p "$(dirname "$PREFIX_HEADER")"
cat > "$PREFIX_HEADER" << EOF
#define kDriver_Name "$DRIVER_NAME"
#define kPlugIn_BundleID "$BUNDLE_ID"
#define kDevice_Name "$DEVICE_NAME"
#define kDevice_UID "$DEVICE_UID"
#define kDevice_HasInput $kDevice_HasInput
#define kDevice_HasOutput $kDevice_HasOutput
#define kDevice2_IsHidden true
#define kNumber_Of_Channels $CHANNELS
#define kStream_BasicDescription_SampleRate $SAMPLE_RATE
EOF

xcodebuild \
  -project "$BH_PROJECT" \
  -scheme "BlackHole" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  MACOSX_DEPLOYMENT_TARGET=10.13 \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  OTHER_CFLAGS='$(inherited) -include '"$PREFIX_HEADER" \
  | grep -E "^(error:|warning:|Build succeeded|** BUILD)" || true
 
if [[ ! -d "$PRODUCTS/BlackHole.driver" ]]; then
  echo "✖ Build failed — no .driver bundle found in $PRODUCTS"
  exit 1
fi
 
rm -rf "$DRIVER_OUT"
cp -r "$PRODUCTS/BlackHole.driver" "$DRIVER_OUT"
echo "  Built → $DRIVER_OUT"
 
# ── Sign ─────────────────────────────────────────────────────────
if [[ "$SKIP_NOTARIZE" == false ]]; then
  echo "▶ Signing $DRIVER_BUNDLE_NAME..."
  codesign \
    --force \
    --deep \
    --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp \
    "$DRIVER_OUT"
 
  codesign --verify --deep --strict "$DRIVER_OUT"
  echo "  Signed ✓"
 
  # ── Notarize ──────────────────────────────────────────────────
  echo "▶ Notarizing (this takes ~1–5 min)..."
  rm -f "$ZIP_OUT"
  ditto -c -k --keepParent "$DRIVER_OUT" "$ZIP_OUT"
 
  xcrun notarytool submit "$ZIP_OUT" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$NOTARYTOOL_PASSWORD" \
    --wait \
    --output-format plist \
    | tee /tmp/notarytool-result.plist
 
  STATUS=$(plutil -extract "status" raw /tmp/notarytool-result.plist 2>/dev/null || echo "unknown")
  if [[ "$STATUS" != "Accepted" ]]; then
    echo "✖ Notarization failed (status: $STATUS). Check /tmp/notarytool-result.plist"
    exit 1
  fi
 
  echo "▶ Stapling notarization ticket..."
  xcrun stapler staple "$DRIVER_OUT"
  echo "  Stapled ✓"
else
  echo "  ⚠ Skipping sign + notarize (dev build only — do not ship this)"
fi
 
echo ""
echo "✔ Done: $DRIVER_OUT"
echo "  Next: run ./scripts/install.sh to install it locally for testing"
