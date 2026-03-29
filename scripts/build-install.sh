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

# --- Selective KolCore cache invalidation ---
# Xcode's incremental build doesn't reliably detect changes in local Swift
# packages (wholemodule compilation). Instead of nuking all DerivedData (330MB,
# minutes to rebuild), we delete only KolCore + Kol artifacts (~21MB, seconds).
DD_DIR=$(find ~/Library/Developer/Xcode/DerivedData/Kol-*/Build -maxdepth 0 2>/dev/null | head -1)
if [ -n "$DD_DIR" ]; then
  KOLCORE_OBJ="$DD_DIR/Products/$CONFIG/KolCore.o"
  if [ -f "$KOLCORE_OBJ" ]; then
    # Check if any KolCore source is newer than the cached build product
    NEWER=$(find KolCore/Sources KolCore/Package.swift -newer "$KOLCORE_OBJ" -print -quit 2>/dev/null)
    if [ -n "$NEWER" ]; then
      echo "KolCore sources changed — cleaning KolCore cache..."
      rm -rf "$DD_DIR/Intermediates.noindex/KolCore.build"
      rm -rf "$DD_DIR/Intermediates.noindex/Kol.build"
      rm -f  "$DD_DIR/Products/$CONFIG/KolCore.o"
      rm -rf "$DD_DIR/Products/$CONFIG/KolCore.swiftmodule"
      rm -f  "$DD_DIR/Intermediates.noindex/GeneratedModuleMaps/KolCore"*
    fi
  fi
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

echo "Installing to /Applications/Kol.app..."
rsync -a --delete "$APP_PATH/" /Applications/Kol.app/

echo "Done. Launch with: open /Applications/Kol.app"
