#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: ./scripts/release.sh <major.minor.patch>" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: Working tree is not clean." >&2
  exit 1
fi

REMOTE=origin
REPO=alandotcom/Kol
BRANCH=$(git branch --show-current)
if [[ "$BRANCH" != main ]]; then
  echo "ERROR: Release from main." >&2
  exit 1
fi
git fetch "$REMOTE" main --tags
if ! git merge-base --is-ancestor "$REMOTE/main" HEAD; then
  echo "ERROR: Local main is behind or diverged from origin/main." >&2
  exit 1
fi
if git rev-parse --verify "refs/tags/v${VERSION}" >/dev/null 2>&1; then
  echo "ERROR: Tag v${VERSION} already exists." >&2
  exit 1
fi
gh api "repos/${REPO}" >/dev/null

NOTARY_PROFILE="${KOL_NOTARY_PROFILE:-kol-notary}"
echo "Checking notarization credentials for Keychain profile ${NOTARY_PROFILE}..."
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null; then
  echo "ERROR: Notarization credentials are unavailable. Run: xcrun notarytool store-credentials \"${NOTARY_PROFILE}\"" >&2
  exit 1
fi

SPARKLE_TOOLS=$(./scripts/sparkle-tools.sh)
SPARKLE_ACCOUNT="${KOL_SPARKLE_ACCOUNT:-kol-updates}"
echo "Checking Sparkle signing key in Keychain account ${SPARKLE_ACCOUNT}..."
if ! PUBLIC_KEY=$("$SPARKLE_TOOLS/generate_keys" --account "$SPARKLE_ACCOUNT" -p); then
  echo "ERROR: Sparkle key is unavailable. Run: \"$SPARKLE_TOOLS/generate_keys\" --account \"$SPARKLE_ACCOUNT\"" >&2
  exit 1
fi
python3 - "$PUBLIC_KEY" <<'PY'
import plistlib, sys
from pathlib import Path
info = plistlib.loads(Path('Kol/Info.plist').read_bytes())
if sys.argv[1].strip() != info.get('SUPublicEDKey'):
    raise SystemExit('ERROR: Keychain signing key does not match SUPublicEDKey. Restore the original Sparkle key before releasing.')
PY

ARTIFACT_DIR="$PWD/build"
VERIFY_DIR="${ARTIFACT_DIR}/verification/release-${VERSION}"
DERIVED_DATA_PATH="${KOL_DERIVED_DATA_PATH:-$PWD/build/DerivedData}"
mkdir -p "$VERIFY_DIR"
python3 scripts/prepare-release.py "$VERSION" "$VERIFY_DIR/notes.md"

echo "Testing Kol ${VERSION}..."
xcodebuildmcp macos test --project-path "$PWD/Kol.xcodeproj" --scheme Kol \
  --derived-data-path "$DERIVED_DATA_PATH" \
  --json '{"extraArgs":["-skipMacroValidation","-skipPackagePluginValidation"]}' \
  > "$VERIFY_DIR/tests.log" 2>&1
if ! grep -Eq '([0-9]+ tests passed, 0 failed|Overall Result: Passed)' "$VERIFY_DIR/tests.log"; then
  echo "ERROR: Test log has no passing result. See ${VERIFY_DIR}/tests.log." >&2
  exit 1
fi

echo "Building Release..."
./scripts/build-install.sh --release > "$VERIFY_DIR/build.log" 2>&1
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/Kol.app"
codesign --verify --deep --strict "$APP_PATH" > "$VERIFY_DIR/signature.log" 2>&1
python3 - "$APP_PATH" "$VERSION" <<'PY'
import plistlib, sys
from pathlib import Path
info = plistlib.loads((Path(sys.argv[1]) / 'Contents/Info.plist').read_bytes())
if info['CFBundleShortVersionString'] != sys.argv[2] or info['CFBundleIdentifier'] != 'com.alandotcom.Kol':
    raise SystemExit('ERROR: Release artifact metadata does not match the requested release.')
PY

ZIP_PATH="${ARTIFACT_DIR}/Kol-v${VERSION}.zip"
SUBMISSION_ZIP="$VERIFY_DIR/notarization-submission.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SUBMISSION_ZIP"
echo "Submitting Kol ${VERSION} for notarization..."
NOTARY_EXIT=0
xcrun notarytool submit "$SUBMISSION_ZIP" --keychain-profile "$NOTARY_PROFILE" \
  --wait --timeout "${KOL_NOTARY_TIMEOUT:-1h}" --output-format json \
  > "$VERIFY_DIR/notarization.json" 2> "$VERIFY_DIR/notarization-stderr.log" || NOTARY_EXIT=$?
SUBMISSION_ID=$(python3 - "$VERIFY_DIR/notarization.json" <<'PY'
import json, sys
from pathlib import Path
try:
    print(json.loads(Path(sys.argv[1]).read_text()).get('id', ''))
except (ValueError, OSError):
    pass
PY
)
if [[ -n "$SUBMISSION_ID" ]]; then
  xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" \
    "$VERIFY_DIR/notarization-log.json" > "$VERIFY_DIR/notarization-log-command.log" 2>&1 || true
fi
if [[ "$NOTARY_EXIT" != 0 ]]; then
  echo "ERROR: Notarization failed or timed out. See ${VERIFY_DIR}/notarization*." >&2
  exit 1
fi
python3 - "$VERIFY_DIR/notarization.json" <<'PY'
import json, sys
from pathlib import Path
result = json.loads(Path(sys.argv[1]).read_text())
if result.get('status') != 'Accepted':
    raise SystemExit(f"ERROR: Notarization status is {result.get('status', 'unknown')}. See {sys.argv[1]} and notarization-log.json.")
PY

echo "Stapling and verifying the notarization ticket..."
xcrun stapler staple "$APP_PATH" > "$VERIFY_DIR/staple.log" 2>&1
xcrun stapler validate "$APP_PATH" > "$VERIFY_DIR/staple-validation.log" 2>&1
codesign --verify --deep --strict "$APP_PATH" > "$VERIFY_DIR/signature.log" 2>&1
spctl --assess --type execute --verbose=2 "$APP_PATH" > "$VERIFY_DIR/gatekeeper.log" 2>&1

# ZIP files cannot be stapled. Package the app after attaching its ticket.
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
unzip -tq "$ZIP_PATH" > "$VERIFY_DIR/archive.log"
EXTRACT_DIR="$VERIFY_DIR/extracted"
rm -rf "$EXTRACT_DIR"
ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"
xcrun stapler validate "$EXTRACT_DIR/Kol.app" > "$VERIFY_DIR/archive-staple-validation.log" 2>&1
codesign --verify --deep --strict "$EXTRACT_DIR/Kol.app" > "$VERIFY_DIR/archive-signature.log" 2>&1
shasum -a 256 "$ZIP_PATH" > "$VERIFY_DIR/sha256.txt"

echo "Generating and verifying the signed update feed..."
FEED_DIR="$VERIFY_DIR/feed"
rm -rf "$FEED_DIR"
mkdir -p "$FEED_DIR"
cp "$ZIP_PATH" "$FEED_DIR/"
cp "$VERIFY_DIR/notes.md" "$FEED_DIR/Kol-v${VERSION}.md"
"$SPARKLE_TOOLS/generate_appcast" --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "https://github.com/${REPO}/releases/download/v${VERSION}/" \
  --embed-release-notes --maximum-deltas 0 "$FEED_DIR" > "$VERIFY_DIR/appcast.log" 2>&1
FEED_PATH="$FEED_DIR/appcast.xml"
python3 scripts/verify-appcast.py "$FEED_PATH" "$ZIP_PATH" "$APP_PATH" \
  "$SPARKLE_TOOLS" "$SPARKLE_ACCOUNT" \
  "https://github.com/${REPO}/releases/download/v${VERSION}/Kol-v${VERSION}.zip" \
  > "$VERIFY_DIR/appcast-verification.log" 2>&1

git diff --check
git add Kol/Info.plist Kol.xcodeproj/project.pbxproj package.json \
  CHANGELOG.md Kol/Resources/changelog.md .changeset
git commit -m "Release v${VERSION}" -m "Collect pending changesets and synchronize app version metadata and changelogs."
git tag "v${VERSION}"
git push --atomic "$REMOTE" "$BRANCH" "v${VERSION}"

gh release create "v${VERSION}" "$ZIP_PATH" "$FEED_PATH" --repo "$REPO" \
  --title "Kol v${VERSION}" --notes-file "$VERIFY_DIR/notes.md" --draft --verify-tag
gh release view "v${VERSION}" --repo "$REPO" --json assets > "$VERIFY_DIR/upload.json"
python3 - "$VERIFY_DIR/upload.json" "$ZIP_PATH" "$FEED_PATH" <<'PY'
import hashlib, json, sys
from pathlib import Path
assets = json.loads(Path(sys.argv[1]).read_text())['assets']
for filename in sys.argv[2:]:
    artifact = Path(filename)
    asset = next((a for a in assets if a['name'] == artifact.name), None)
    digest = 'sha256:' + hashlib.sha256(artifact.read_bytes()).hexdigest()
    if not asset or asset['state'] != 'uploaded' or asset['size'] != artifact.stat().st_size or asset.get('digest') != digest:
        raise SystemExit(f'ERROR: Uploaded {artifact.name} failed verification. Release remains a draft.')
PY
gh release edit "v${VERSION}" --repo "$REPO" --draft=false --latest
echo "Released https://github.com/${REPO}/releases/tag/v${VERSION}"
