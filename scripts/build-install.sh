#!/bin/bash
set -euo pipefail

# Build (unsigned), then codesign with stable identity, then install.
# Rebuilds can require renewed macOS privacy grants even with the same identity.
#
# Usage: ./scripts/build-install.sh [--debug | --resolve-packages]
#   --debug  Build with Debug configuration (faster incremental builds)
#   --resolve-packages  Resolve dependencies without building, signing, or installing

cd "$(dirname "$0")/.."

DERIVED_DATA_PATH="${KOL_DERIVED_DATA_PATH:-$PWD/build/DerivedData}"
if [[ "${1:-}" == "--resolve-packages" ]]; then
  exec xcodebuild -resolvePackageDependencies \
    -project Kol.xcodeproj -scheme Kol -derivedDataPath "$DERIVED_DATA_PATH"
fi

CONFIG=Release
if [[ "${1:-}" == "--debug" ]]; then
  CONFIG=Debug
fi

# Kill running Kol before building.
# Kol registers an active CGEvent tap (kernel-level, synchronous) for hotkeys.
# If the app is running during a heavy build, the main thread gets CPU-starved
# and the tap callback can't fire — macOS blocks ALL system input waiting for it,
# freezing mouse + keyboard until the process is killed or the tap times out.
if [[ "$CONFIG" == "Debug" ]]; then
  APP_NAME="Kol Debug"
else
  APP_NAME="Kol"
fi
# Match the installed executable path so debug builds leave production Kol running.
pkill -f "^/Applications/${APP_NAME}\.app/Contents/MacOS/Kol([[:space:]]|$)" 2>/dev/null && sleep 0.5 || true

JOBS=$(sysctl -n hw.ncpu)
echo "Building $CONFIG (${JOBS} parallel jobs)..."
xcodebuild build \
  -project Kol.xcodeproj \
  -scheme Kol \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -configuration "$CONFIG" \
  -jobs "$JOBS" \
  -parallelizeTargets \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  2>&1

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIG/Kol.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Expected $CONFIG app at $APP_PATH"
  exit 1
fi

echo "Signing..."
codesign --deep --force --sign "Developer ID Application: Alan Cohen (G365XP38PA)" "$APP_PATH"

if [[ "$CONFIG" == "Debug" ]]; then
  echo "Installing to /Applications/Kol Debug.app..."
  rsync -a --delete "$APP_PATH/" "/Applications/Kol Debug.app/"
  echo "Done. Launch with: open \"/Applications/Kol Debug.app\""
else
  echo "Installing to /Applications/Kol.app..."
  rsync -a --delete "$APP_PATH/" /Applications/Kol.app/
  echo "Done. Launch with: open /Applications/Kol.app"
fi
