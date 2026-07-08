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

sign_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    /usr/bin/codesign --force --sign - --timestamp=none "$path"
  fi
}

sign_for_unsigned_distribution() {
  sign_if_exists "$APP_BUNDLE/Contents/Resources/ffmpeg/libmp3lame.0.dylib"
  sign_if_exists "$APP_BUNDLE/Contents/Resources/ffmpeg/ffmpeg"
  sign_if_exists "$APP_BUNDLE/Contents/Resources/ncmdump/bin/libtag.2.dylib"
  sign_if_exists "$APP_BUNDLE/Contents/Resources/ncmdump/bin/ncmdump"
  sign_if_exists "$APP_BUNDLE/Contents/Resources/apple-music-downloader/apple-music-downloader"
  sign_if_exists "$APP_BUNDLE/Contents/Frameworks/GetOudioCore.framework"
  sign_if_exists "$APP_BUNDLE/Contents/PlugIns/GetOudioFinderExtension.appex"
  sign_if_exists "$APP_BUNDLE/Contents/PlugIns/GetOudioShareExtension.appex"
  sign_if_exists "$APP_BUNDLE/Contents/Library/LoginItems/$AGENT_NAME.app/Contents/Frameworks/GetOudioCore.framework"
  sign_if_exists "$APP_BUNDLE/Contents/Library/LoginItems/$AGENT_NAME.app"
  sign_if_exists "$APP_BUNDLE"
  /usr/bin/codesign --verify --strict --deep --verbose=2 "$APP_BUNDLE"
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
sign_for_unsigned_distribution
create_dmg

echo "DMG written to: $DMG_OUTPUT"
echo "This DMG is ad hoc signed and not notarized. Recipients may need to right-click Open or remove Gatekeeper quarantine:"
echo "  xattr -dr com.apple.quarantine \"/Applications/$APP_NAME.app\""
