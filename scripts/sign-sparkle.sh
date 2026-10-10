#!/bin/bash
set -euo pipefail

# Xcode's Code Sign on Copy does not sign Sparkle's nested installer helpers.
# Run after embedding frameworks, before Xcode signs the outer app.
if [[ "${CODE_SIGNING_ALLOWED:-NO}" != YES ]]; then
  exit 0
fi
FRAMEWORK="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/Sparkle.framework"
for COMPONENT in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime \
    --timestamp --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/$COMPONENT"
done
/usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime \
  --timestamp "$FRAMEWORK"
