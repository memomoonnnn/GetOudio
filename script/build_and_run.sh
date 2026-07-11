#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
SCHEME="GetOudio"
APP_NAME="Get Oudio"
AGENT_NAME="GetOudioAMRuntimeAgent"
BUNDLE_ID="com.shengjiacheng.GetOudio"
FINDER_EXTENSION_ID="com.shengjiacheng.GetOudio.FinderExtension"
FINDER_EXTENSION_POINT_ID="com.apple.FinderSync"
SHARE_EXTENSION_POINT_ID="com.apple.share-services"
APP_GROUP_ID="group.com.shengjiacheng.GetOudio"
DIAGNOSTIC_SHARED_CONTAINER_KEY="GET_OUDIO_DIAGNOSTIC_SHARED_CONTAINER_ROOT"
SHARE_EXTENSION_ID="com.shengjiacheng.GetOudio.ShareExtension"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
DEBUG_CONFIGURATION="Debug"
INSTALL_CONFIGURATION="${INSTALL_CONFIGURATION:-Release}"
DEBUG_APP_BUNDLE="$DERIVED_DATA/Build/Products/$DEBUG_CONFIGURATION/$APP_NAME.app"
INSTALL_APP_BUNDLE="$DERIVED_DATA/Build/Products/$INSTALL_CONFIGURATION/$APP_NAME.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
LEGACY_USER_APP="$HOME/Applications/$APP_NAME.app"

cd "$ROOT_DIR"

if [[ ! -d "$ROOT_DIR/GetOudio.xcodeproj" ]]; then
  xcodegen generate
fi

stop_running_processes() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -x "$AGENT_NAME" >/dev/null 2>&1 || true
}

verify_embedded_agent() {
  local configuration="$1"
  local app_bundle="$DERIVED_DATA/Build/Products/$configuration/$APP_NAME.app"
  local built_agent="$DERIVED_DATA/Build/Products/$configuration/$AGENT_NAME.app/Contents/MacOS/$AGENT_NAME"
  local embedded_agent="$app_bundle/Contents/Library/LoginItems/$AGENT_NAME.app/Contents/MacOS/$AGENT_NAME"

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

stop_running_processes

build_unsigned() {
  xcodebuild \
    -project "$ROOT_DIR/GetOudio.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$DEBUG_CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build
  verify_embedded_agent "$DEBUG_CONFIGURATION"
}

build_signed() {
  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    xcodebuild \
      -allowProvisioningUpdates \
      -project "$ROOT_DIR/GetOudio.xcodeproj" \
      -scheme "$SCHEME" \
      -configuration "$INSTALL_CONFIGURATION" \
      -derivedDataPath "$DERIVED_DATA" \
      CODE_SIGNING_ALLOWED=YES \
      CODE_SIGN_STYLE=Automatic \
      DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
      clean \
      build
    verify_embedded_agent "$INSTALL_CONFIGURATION"
    return
  fi

  xcodebuild \
    -allowProvisioningUpdates \
    -project "$ROOT_DIR/GetOudio.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$INSTALL_CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_STYLE=Automatic \
    clean \
    build
  verify_embedded_agent "$INSTALL_CONFIGURATION"
}

open_app() {
  /usr/bin/open -n \
    --env "$DIAGNOSTIC_SHARED_CONTAINER_KEY=$ROOT_DIR/build/DiagnosticSharedContainer" \
    "$DEBUG_APP_BUNDLE"
}

verify_entitlements() {
  local bundle_path="$1"
  local entitlements_file
  entitlements_file="$(mktemp)"

  if ! /usr/bin/codesign --verify --strict --verbose=4 "$bundle_path"; then
    echo "invalid code signature in $bundle_path" >&2
    rm -f "$entitlements_file"
    exit 1
  fi

  if ! /usr/bin/codesign -d --entitlements :- "$bundle_path" >"$entitlements_file" 2>/dev/null; then
    echo "failed to read entitlements from $bundle_path" >&2
    rm -f "$entitlements_file"
    exit 1
  fi

  if ! /usr/bin/grep -q "com.apple.security.app-sandbox" "$entitlements_file"; then
    echo "missing sandbox entitlement in $bundle_path" >&2
    /bin/cat "$entitlements_file" >&2
    rm -f "$entitlements_file"
    exit 1
  fi

  if ! /usr/bin/grep -q "com.apple.security.application-groups" "$entitlements_file" ||
     ! /usr/bin/grep -q "$APP_GROUP_ID" "$entitlements_file"; then
    echo "missing app group entitlement in $bundle_path" >&2
    /bin/cat "$entitlements_file" >&2
    rm -f "$entitlements_file"
    exit 1
  fi

  if ! /usr/bin/grep -q "com.apple.security.files.bookmarks.app-scope" "$entitlements_file"; then
    echo "missing app-scope bookmark entitlement in $bundle_path" >&2
    /bin/cat "$entitlements_file" >&2
    rm -f "$entitlements_file"
    exit 1
  fi

  rm -f "$entitlements_file"
}

verify_extension_point() {
  local bundle_path="$1"
  local expected_extension_point="$2"
  local info_plist="$bundle_path/Contents/Info.plist"
  local actual_extension_point

  actual_extension_point="$(/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPointIdentifier" "$info_plist" 2>/dev/null || true)"

  if [[ "$actual_extension_point" != "$expected_extension_point" ]]; then
    echo "missing or wrong NSExtensionPointIdentifier in $bundle_path" >&2
    /usr/bin/plutil -p "$info_plist" >&2
    exit 1
  fi
}

verify_url_scheme() {
  local bundle_path="$1"
  local info_plist="$bundle_path/Contents/Info.plist"
  local schemes

  schemes="$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes" "$info_plist" 2>/dev/null || true)"

  if ! /usr/bin/grep -q "getoudio" <<<"$schemes"; then
    echo "missing getoudio URL scheme in $bundle_path" >&2
    /usr/bin/plutil -p "$info_plist" >&2
    exit 1
  fi
}

unregister_existing_plugins() {
  local bundle_path

  pluginkit -e ignore -i "$FINDER_EXTENSION_ID" >/dev/null 2>&1 || true
  pluginkit -e ignore -i "$SHARE_EXTENSION_ID" >/dev/null 2>&1 || true

  while IFS= read -r bundle_path; do
    [[ -n "$bundle_path" ]] || continue
    pluginkit -r "$bundle_path" >/dev/null 2>&1 || true
  done < <(
    /usr/bin/mdfind \
      "kMDItemCFBundleIdentifier == '$BUNDLE_ID' || kMDItemCFBundleIdentifier == '$FINDER_EXTENSION_ID' || kMDItemCFBundleIdentifier == '$SHARE_EXTENSION_ID'" \
      2>/dev/null || true
  )

  local candidates=(
    "$INSTALLED_APP"
    "$LEGACY_USER_APP"
    "$DEBUG_APP_BUNDLE"
    "$INSTALL_APP_BUNDLE"
    "$INSTALLED_APP/Contents/PlugIns/GetOudioFinderExtension.appex"
    "$INSTALLED_APP/Contents/PlugIns/GetOudioShareExtension.appex"
    "$LEGACY_USER_APP/Contents/PlugIns/GetOudioFinderExtension.appex"
    "$LEGACY_USER_APP/Contents/PlugIns/GetOudioShareExtension.appex"
    "$DEBUG_APP_BUNDLE/Contents/PlugIns/GetOudioFinderExtension.appex"
    "$DEBUG_APP_BUNDLE/Contents/PlugIns/GetOudioShareExtension.appex"
    "$INSTALL_APP_BUNDLE/Contents/PlugIns/GetOudioFinderExtension.appex"
    "$INSTALL_APP_BUNDLE/Contents/PlugIns/GetOudioShareExtension.appex"
  )

  for bundle_path in "${candidates[@]}"; do
    pluginkit -r "$bundle_path" >/dev/null 2>&1 || true
  done

  /usr/bin/pkill -x pkd >/dev/null 2>&1 || true
}

install_app() {
  build_signed

  mkdir -p "$INSTALL_DIR"
  unregister_existing_plugins
  rm -rf "$INSTALLED_APP"
  /usr/bin/ditto "$INSTALL_APP_BUNDLE" "$INSTALLED_APP"
  verify_url_scheme "$INSTALLED_APP"
  verify_extension_point "$INSTALLED_APP/Contents/PlugIns/GetOudioFinderExtension.appex" "$FINDER_EXTENSION_POINT_ID"
  verify_extension_point "$INSTALLED_APP/Contents/PlugIns/GetOudioShareExtension.appex" "$SHARE_EXTENSION_POINT_ID"
  verify_entitlements "$INSTALLED_APP"
  verify_entitlements "$INSTALLED_APP/Contents/PlugIns/GetOudioFinderExtension.appex"
  verify_entitlements "$INSTALLED_APP/Contents/PlugIns/GetOudioShareExtension.appex"
  /usr/bin/open -n "$INSTALLED_APP"
  /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$INSTALLED_APP"
  pluginkit -a "$INSTALLED_APP"
  pluginkit -a "$INSTALLED_APP/Contents/PlugIns/GetOudioFinderExtension.appex"
  pluginkit -a "$INSTALLED_APP/Contents/PlugIns/GetOudioShareExtension.appex"
  pluginkit -e use -i "$FINDER_EXTENSION_ID"
  pluginkit -e use -i "$SHARE_EXTENSION_ID"
  killall Finder >/dev/null 2>&1 || true
  pluginkit -m -v -i "$FINDER_EXTENSION_ID"
  pluginkit -m -v -i "$SHARE_EXTENSION_ID"
}

case "$MODE" in
  run)
    build_unsigned
    open_app
    ;;
  --verify|verify)
    build_unsigned
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --logs|logs)
    build_unsigned
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    build_unsigned
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --install|install)
    install_app
    ;;
  --clean-plugins|clean-plugins)
    unregister_existing_plugins
    killall Finder >/dev/null 2>&1 || true
    pluginkit -m -v -i "$FINDER_EXTENSION_ID"
    pluginkit -m -v -i "$SHARE_EXTENSION_ID"
    ;;
  *)
    echo "usage: $0 [run|--verify|--logs|--telemetry|--install|--clean-plugins]" >&2
    exit 2
    ;;
esac
