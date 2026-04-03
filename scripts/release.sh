#!/bin/bash
set -e

# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.0.0
#
# What it does:
# 1. Bumps version in Info.plist, project.pbxproj, package.json
# 2. Increments build number
# 3. Commits version bump + creates git tag
# 4. Builds, signs, creates ZIP
# 5. Pushes to GitHub + creates release with ZIP attached

cd "$(dirname "$0")/.."

VERSION="$1"
if [ -z "$VERSION" ]; then
  echo "Usage: ./scripts/release.sh <version>"
  echo "Example: ./scripts/release.sh 1.0.0"
  exit 1
fi

# Validate semver format
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "ERROR: Version must be semver (e.g. 1.0.0)"
  exit 1
fi

# Check for clean working tree (allow staged changes)
if [ -n "$(git diff HEAD 2>/dev/null)" ] || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo "ERROR: Working tree is not clean. Commit or stash changes first."
  exit 1
fi

REMOTE="origin"
BRANCH=$(git branch --show-current)

echo "==> Releasing Kol v${VERSION} from branch ${BRANCH}"

# --- 1. Bump version numbers ---

# Get current build number and increment
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' Kol.xcodeproj/project.pbxproj | tr -dc '0-9')
NEW_BUILD=$((CURRENT_BUILD + 1))

echo "  Version: ${VERSION} (build ${NEW_BUILD})"

# Info.plist
sed -i '' "s|<string>[0-9]*\.[0-9]*\.[0-9]*</string><!-- MARKETING -->|<string>${VERSION}</string><!-- MARKETING -->|" Kol/Info.plist 2>/dev/null || true
# Use a more reliable approach: find the line after CFBundleShortVersionString and replace its value
python3 -c "
import plistlib, pathlib
p = pathlib.Path('Kol/Info.plist')
d = plistlib.loads(p.read_bytes())
d['CFBundleShortVersionString'] = '${VERSION}'
d['CFBundleVersion'] = '${NEW_BUILD}'
p.write_bytes(plistlib.dumps(d, fmt=plistlib.FMT_XML))
"

# project.pbxproj — update all MARKETING_VERSION and CURRENT_PROJECT_VERSION
sed -i '' "s/MARKETING_VERSION = [0-9]*\.[0-9]*\.[0-9]*/MARKETING_VERSION = ${VERSION}/g" Kol.xcodeproj/project.pbxproj
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*/CURRENT_PROJECT_VERSION = ${NEW_BUILD}/g" Kol.xcodeproj/project.pbxproj

# package.json
sed -i '' "s/\"version\": \"[0-9]*\.[0-9]*\.[0-9]*\"/\"version\": \"${VERSION}\"/" package.json

echo "  Updated Info.plist, project.pbxproj, package.json"

# --- 2. Commit + tag ---

git add Kol/Info.plist Kol.xcodeproj/project.pbxproj package.json
git commit -m "$(cat <<EOF
Release v${VERSION}

Build ${NEW_BUILD}
EOF
)"

git tag "v${VERSION}"
echo "  Created commit + tag v${VERSION}"

# --- 3. Build ---

echo "==> Building..."
killall Kol 2>/dev/null || true
rm -rf ~/Library/Developer/Xcode/DerivedData/Kol-*

xcodebuild build \
  -scheme Kol \
  -configuration Release \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tail -1

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Kol-*/Build/Products/Release/Kol.app -maxdepth 0 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
  echo "ERROR: No Release build found"
  exit 1
fi

# --- 4. Sign ---

echo "==> Signing..."
codesign --deep --force --sign "Apple Development: alan.mit@gmail.com (97Y8HW2AB7)" "$APP_PATH"

# --- 5. Create ZIP ---

ARTIFACT_DIR="$(pwd)/build"
mkdir -p "$ARTIFACT_DIR"
ZIP_PATH="${ARTIFACT_DIR}/Kol-v${VERSION}.zip"

echo "==> Creating ZIP..."
cd "$(dirname "$APP_PATH")"
zip -r -q "$ZIP_PATH" Kol.app
cd ->/dev/null

echo "  ${ZIP_PATH}"

# --- 6. Push + GitHub release ---

echo "==> Pushing to ${REMOTE}..."
git push "$REMOTE" "$BRANCH"
git push "$REMOTE" "v${VERSION}"

echo "==> Creating GitHub release..."
gh release create "v${VERSION}" \
  "$ZIP_PATH" \
  --repo alandotcom/Kol \
  --title "Kol v${VERSION}" \
  --generate-notes

echo ""
echo "==> Done! Release: https://github.com/alandotcom/Kol/releases/tag/v${VERSION}"
