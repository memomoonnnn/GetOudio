#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/build/DerivedData}"
GENERATE_APPCAST="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"

usage() {
  echo "Usage: $0 <release-dmg> <github-release-tag>" >&2
  echo "Example: $0 build/GetOudio-1.1.2.dmg v1.1.2" >&2
  exit 64
}

[[ $# -eq 2 ]] || usage

DMG_PATH="$1"
RELEASE_TAG="$2"

if [[ ! -f "$DMG_PATH" || "${DMG_PATH##*.}" != "dmg" ]]; then
  echo "release DMG not found: $DMG_PATH" >&2
  exit 1
fi

if [[ ! -x "$GENERATE_APPCAST" ]]; then
  echo "Sparkle tools are unavailable; resolve the GetOudio package dependencies first." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cp "$DMG_PATH" "$WORK_DIR/$(basename "$DMG_PATH")"
cp "$ROOT_DIR/appcast.xml" "$WORK_DIR/appcast.xml"

"$GENERATE_APPCAST" \
  --download-url-prefix "https://github.com/memomoonnnn/GetOudio/releases/download/$RELEASE_TAG/" \
  --link "https://github.com/memomoonnnn/GetOudio/releases" \
  --maximum-deltas 0 \
  --maximum-versions 3 \
  "$WORK_DIR"

cp "$WORK_DIR/appcast.xml" "$ROOT_DIR/appcast.xml"
echo "Updated $ROOT_DIR/appcast.xml"
