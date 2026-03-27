#!/bin/bash
set -e

# Build Release (unsigned), then codesign with stable identity, then install.
# Permissions persist between installs because the signature is stable.

cd "$(dirname "$0")/.."

echo "Building Release..."
xcodebuild build \
  -scheme Hex \
  -configuration Release \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tail -1

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Hex-*/Build/Products/Release/Hex.app -maxdepth 0 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
  echo "ERROR: No Release build found"
  exit 1
fi

echo "Signing..."
codesign --deep --force --sign "Apple Development: alan.mit@gmail.com (97Y8HW2AB7)" "$APP_PATH"

echo "Installing to /Applications/Hex.app..."
rsync -a --delete "$APP_PATH/" /Applications/Hex.app/

echo "Done. Launch with: open /Applications/Hex.app"
