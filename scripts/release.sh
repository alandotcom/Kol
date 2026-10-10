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
if ! grep -q 'Overall Result: Passed' "$VERIFY_DIR/tests.log"; then
  echo "ERROR: Test log has no passing result. See ${VERIFY_DIR}/tests.log." >&2
  exit 1
fi

echo "Building Release..."
./scripts/build-install.sh > "$VERIFY_DIR/build.log" 2>&1
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
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
unzip -tq "$ZIP_PATH" > "$VERIFY_DIR/archive.log"
shasum -a 256 "$ZIP_PATH" > "$VERIFY_DIR/sha256.txt"

git diff --check
git add Kol/Info.plist Kol.xcodeproj/project.pbxproj package.json \
  CHANGELOG.md Kol/Resources/changelog.md .changeset
git commit -m "Release v${VERSION}" -m "Collect pending changesets and synchronize app version metadata and changelogs."
git tag "v${VERSION}"
git push --atomic "$REMOTE" "$BRANCH" "v${VERSION}"

gh release create "v${VERSION}" "$ZIP_PATH" --repo "$REPO" \
  --title "Kol v${VERSION}" --notes-file "$VERIFY_DIR/notes.md" --draft --verify-tag
gh release view "v${VERSION}" --repo "$REPO" --json assets > "$VERIFY_DIR/upload.json"
python3 - "$VERIFY_DIR/upload.json" "$ZIP_PATH" <<'PY'
import hashlib, json, sys
from pathlib import Path
archive = Path(sys.argv[2])
assets = json.loads(Path(sys.argv[1]).read_text())['assets']
asset = next((a for a in assets if a['name'] == archive.name), None)
digest = 'sha256:' + hashlib.sha256(archive.read_bytes()).hexdigest()
if not asset or asset['state'] != 'uploaded' or asset['size'] != archive.stat().st_size or asset.get('digest') != digest:
    raise SystemExit('ERROR: Uploaded release archive failed verification. Release remains a draft.')
PY
gh release edit "v${VERSION}" --repo "$REPO" --draft=false --latest
echo "Released https://github.com/${REPO}/releases/tag/v${VERSION}"
