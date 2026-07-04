#!/usr/bin/env bash
set -euo pipefail

SCHEME="GetOudio"
APP_NAME="Get Oudio"
AGENT_NAME="GetOudioAMRuntimeAgent"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/build/DerivedData}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
AGENT_APP="$BUILD_DIR/$AGENT_NAME.app"
DMG_WORK_DIR="${DMG_WORK_DIR:-$ROOT_DIR/build/dmg}"
DMG_ROOT="$DMG_WORK_DIR/root"
DMG_OUTPUT="${DMG_OUTPUT:-$ROOT_DIR/build/GetOudio.dmg}"
VOLUME_NAME="${VOLUME_NAME:-Get Oudio}"

cd "$ROOT_DIR"

if [[ ! -d "$ROOT_DIR/GetOudio.xcodeproj" ]]; then
  xcodegen generate
fi

build_app() {
  local xcodebuild_args=(
    -allowProvisioningUpdates
    -project "$ROOT_DIR/GetOudio.xcodeproj"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$DERIVED_DATA"
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGN_STYLE=Automatic
    clean
    build
  )

  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    xcodebuild "${xcodebuild_args[@]}" DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
  else
    xcodebuild "${xcodebuild_args[@]}"
  fi
}

verify_embedded_agent() {
  local built_agent="$AGENT_APP/Contents/MacOS/$AGENT_NAME"
  local embedded_agent="$APP_BUNDLE/Contents/Library/LoginItems/$AGENT_NAME.app/Contents/MacOS/$AGENT_NAME"

  if [[ ! -x "$built_agent" ]]; then
    echo "missing built Apple Music Runtime Agent executable: $built_agent" >&2
    exit 1
  fi
  if [[ ! -x "$embedded_agent" ]]; then
    echo "missing embedded Apple Music Runtime Agent executable: $embedded_agent" >&2
    exit 1
  fi
  if ! cmp -s "$built_agent" "$embedded_agent"; then
    echo "embedded Apple Music Runtime Agent is stale: $embedded_agent" >&2
    exit 1
  fi
}

create_dmg() {
  rm -rf "$DMG_WORK_DIR"
  mkdir -p "$DMG_ROOT"
  /usr/bin/ditto "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
  ln -s /Applications "$DMG_ROOT/Applications"
  mkdir -p "$(dirname "$DMG_OUTPUT")"
  rm -f "$DMG_OUTPUT"
  /usr/bin/hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT"
}

build_app
verify_embedded_agent
create_dmg

echo "DMG written to: $DMG_OUTPUT"
echo "This DMG is not notarized. Recipients may need to right-click Open or remove Gatekeeper quarantine:"
echo "  xattr -dr com.apple.quarantine \"/Applications/$APP_NAME.app\""
