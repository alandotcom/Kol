#!/bin/bash
set -e

# Build (unsigned), then codesign with stable identity, then install.
# Permissions persist between installs because the signature is stable.
#
# Usage: ./scripts/build-install.sh [--debug]
#   --debug  Build with Debug configuration (faster incremental builds)

cd "$(dirname "$0")/.."

CONFIG=Release
if [[ "$1" == "--debug" ]]; then
  CONFIG=Debug
fi

JOBS=$(sysctl -n hw.ncpu)
echo "Building $CONFIG (${JOBS} parallel jobs)..."
xcodebuild build \
  -scheme Kol \
  -configuration "$CONFIG" \
  -jobs "$JOBS" \
  -parallelizeTargets \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tail -1

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Kol-*/Build/Products/"$CONFIG"/Kol*.app -maxdepth 0 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
  echo "ERROR: No $CONFIG build found"
  exit 1
fi

echo "Signing..."
codesign --deep --force --sign "Developer ID Application: Alan Cohen (G365XP38PA)" "$APP_PATH"

if [[ "$CONFIG" == "Debug" ]]; then
  echo "Done. Launch with: open \"$APP_PATH\""
else
  echo "Installing to /Applications/Kol.app..."
  rsync -a --delete "$APP_PATH/" /Applications/Kol.app/
  echo "Done. Launch with: open /Applications/Kol.app"
fi
