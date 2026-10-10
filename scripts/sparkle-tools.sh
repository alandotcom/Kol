#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

TOOLS="${KOL_SPARKLE_TOOLS:-$PWD/build/tools/sparkle-2.10.0/bin}"
if [[ -z "${KOL_SPARKLE_TOOLS:-}" && ! -x "$TOOLS/generate_appcast" ]]; then
  ARCHIVE="$PWD/build/tools/Sparkle-2.10.0.tar.xz"
  mkdir -p "$(dirname "$ARCHIVE")"
  curl --fail --location --silent --show-error \
    https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz \
    --output "$ARCHIVE"
  echo "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c  $ARCHIVE" | shasum -a 256 --check >&2
  mkdir -p "$(dirname "$TOOLS")"
  tar -xf "$ARCHIVE" -C "$(dirname "$TOOLS")"
fi
for TOOL in generate_keys generate_appcast sign_update; do
  if [[ ! -x "$TOOLS/$TOOL" ]]; then
    echo "ERROR: Missing Sparkle tool: $TOOLS/$TOOL" >&2
    exit 1
  fi
done
printf '%s\n' "$TOOLS"
