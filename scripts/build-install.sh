#!/bin/bash
set -euo pipefail

# Local builds are unsigned, then signed with a stable identity and installed.
# Distribution builds use Xcode signing and are not installed.
# Rebuilds can require renewed macOS privacy grants even with the same identity.
#
# Usage: ./scripts/build-install.sh [--debug | --release | --resolve-packages]
#   --debug  Build with Debug configuration (faster incremental builds)
#   --release  Build a notarization-ready Release app without installing it
#   --resolve-packages  Resolve dependencies without building, signing, or installing

cd "$(dirname "$0")/.."

DERIVED_DATA_PATH="${KOL_DERIVED_DATA_PATH:-$PWD/build/DerivedData}"
if [[ "${1:-}" == "--resolve-packages" ]]; then
  exec xcodebuild -resolvePackageDependencies \
    -project Kol.xcodeproj -scheme Kol -derivedDataPath "$DERIVED_DATA_PATH"
fi

CONFIG=Release
DISTRIBUTION=false
if [[ "${1:-}" == "--debug" ]]; then
  CONFIG=Debug
elif [[ "${1:-}" == "--release" ]]; then
  DISTRIBUTION=true
elif [[ -n "${1:-}" ]]; then
  echo "ERROR: Unknown build option: $1" >&2
  exit 1
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
if [[ "$DISTRIBUTION" == false ]]; then
  pkill -f "^/Applications/${APP_NAME}\.app/Contents/MacOS/Kol([[:space:]]|$)" 2>/dev/null && sleep 0.5 || true
fi

SIGNING_ARGS=(CODE_SIGNING_ALLOWED=NO)
if [[ "$DISTRIBUTION" == true ]]; then
  # Xcode signs nested frameworks and helpers before the app, with their own entitlements.
  SIGNING_TEAM="${KOL_SIGNING_TEAM:-$(python3 - <<'PY'
import re
from pathlib import Path
project = Path('Kol.xcodeproj/project.pbxproj').read_text()
match = re.search(r'DEVELOPMENT_TEAM = ([A-Z0-9]+);', project)
if not match:
    raise SystemExit('ERROR: Set KOL_SIGNING_TEAM to the Developer ID team ID.')
print(match[1])
PY
)}"
  SIGNING_ARGS=(
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=${KOL_SIGNING_IDENTITY:-Developer ID Application}"
    "DEVELOPMENT_TEAM=$SIGNING_TEAM"
    ENABLE_HARDENED_RUNTIME=YES
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
    OTHER_CODE_SIGN_FLAGS=--timestamp
  )
fi

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
  "${SIGNING_ARGS[@]}" \
  2>&1

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIG/Kol.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Expected $CONFIG app at $APP_PATH"
  exit 1
fi

if [[ "$DISTRIBUTION" == true ]]; then
  codesign --verify --deep --strict "$APP_PATH"
  echo "Done. Distribution app: $APP_PATH"
  exit 0
fi

if [[ -n "${KOL_LOCAL_CLEANUP_MODEL:-}" ]]; then
  if [[ "$CONFIG" != "Debug" || ! -d "$KOL_LOCAL_CLEANUP_MODEL/Cleanup.mlmodelc" ]]; then
    echo "ERROR: A compiled local cleanup model is required for this debug build." >&2
    exit 1
  fi
  mkdir -p "$APP_PATH/Contents/Resources/LocalCleanupModel"
  rsync -a --delete --delete-excluded --exclude="*.mlpackage" "$KOL_LOCAL_CLEANUP_MODEL/" "$APP_PATH/Contents/Resources/LocalCleanupModel/"
else
  # Without a bundled model the app downloads the pinned one from Hugging Face (LocalCleanupModelStore). Incremental
  # builds reuse the previous bundle, so a model bundled by an earlier build is removed.
  rm -rf "$APP_PATH/Contents/Resources/LocalCleanupModel"
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
