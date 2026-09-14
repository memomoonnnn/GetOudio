#!/usr/bin/env bash
set -euo pipefail

SCHEME="GetOudio"
APP_NAME="Get Oudio"
AGENT_PLIST_NAME="com.shengjiacheng.GetOudio.agent.plist"
AGENT_SERVICE_NAME="com.shengjiacheng.GetOudio.agent"
RUNTIME_WORKER_PLIST_NAME="com.shengjiacheng.GetOudio.runtime-worker.plist"
RUNTIME_WORKER_SERVICE_NAME="com.shengjiacheng.GetOudio.runtime-worker"
BOOTSTRAP_INSTALLER_NAME="GetOudioBootstrapInstaller"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/build/DistributionDerivedData}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ENTITLEMENTS_DIR="$ROOT_DIR/build/distribution-entitlements"
DMG_WORK_DIR="${DMG_WORK_DIR:-$ROOT_DIR/build/dmg}"
DMG_ROOT="$DMG_WORK_DIR/root"
DMG_OUTPUT="${DMG_OUTPUT:-$ROOT_DIR/build/GetOudio.dmg}"
VOLUME_NAME="${VOLUME_NAME:-Get Oudio}"

cd "$ROOT_DIR"

xcodegen generate

build_app() {
  xcodebuild \
    -project "$ROOT_DIR/GetOudio.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    "GET_OUDIO_ARCH=${GET_OUDIO_ARCH:-arm64}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    clean \
    build
}

prepare_app_entitlements() {
  rm -rf "$ENTITLEMENTS_DIR"
  mkdir -p "$ENTITLEMENTS_DIR"

  /usr/bin/ditto "$ROOT_DIR/GetOudio/GetOudio.entitlements" "$ENTITLEMENTS_DIR/GetOudio.entitlements"
  /usr/libexec/PlistBuddy \
    -c 'Set :com.apple.security.temporary-exception.mach-lookup.global-name:0 com.shengjiacheng.GetOudio-spks' \
    -c 'Set :com.apple.security.temporary-exception.mach-lookup.global-name:1 com.shengjiacheng.GetOudio-spki' \
    "$ENTITLEMENTS_DIR/GetOudio.entitlements"
}

sign_adhoc() {
  local path="$1"
  shift
  /usr/bin/codesign --force --sign - "$@" "$path"
}

sign_if_present() {
  local path="$1"
  if [[ -e "$path" ]]; then
    sign_adhoc "$path"
  fi
}

sign_distribution_bundle() {
  local sparkle_framework="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
  local sparkle_version="$sparkle_framework/Versions/B"
  local finder_extension="$APP_BUNDLE/Contents/PlugIns/GetOudioFinderExtension.appex"
  local share_extension="$APP_BUNDLE/Contents/PlugIns/GetOudioShareExtension.appex"
  local recording_widget="$APP_BUNDLE/Contents/PlugIns/GetOudioRecordingWidget.appex"
  local runtime_worker="$APP_BUNDLE/Contents/Helpers/GetOudioAMRuntimeWorker.app"
  local bootstrap_installer="$APP_BUNDLE/Contents/Helpers/$BOOTSTRAP_INSTALLER_NAME.app"

  prepare_app_entitlements
  rm -f "$APP_BUNDLE/Contents/embedded.provisionprofile"

  sign_if_present "$APP_BUNDLE/Contents/Resources/ffmpeg/ffmpeg"
  sign_if_present "$APP_BUNDLE/Contents/Resources/ncmdump/bin/libtag.2.dylib"
  sign_if_present "$APP_BUNDLE/Contents/Resources/ncmdump/bin/ncmdump"
  sign_if_present "$APP_BUNDLE/Contents/Resources/apple-music-downloader/apple-music-downloader"

  sign_adhoc "$APP_BUNDLE/Contents/Frameworks/GetOudioCore.framework"

  sign_adhoc "$sparkle_version/XPCServices/Installer.xpc" --preserve-metadata=entitlements
  sign_adhoc "$sparkle_version/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
  sign_adhoc "$sparkle_version/Autoupdate"
  sign_adhoc "$sparkle_version/Updater.app" --preserve-metadata=entitlements
  sign_adhoc "$sparkle_framework"

  sign_adhoc "$finder_extension" --entitlements "$ROOT_DIR/GetOudioFinderExtension/GetOudioFinderExtension.entitlements"
  sign_adhoc "$share_extension" --entitlements "$ROOT_DIR/GetOudioShareExtension/GetOudioShareExtension.entitlements"
  sign_adhoc "$recording_widget" --entitlements "$ROOT_DIR/GetOudioRecordingWidget/GetOudioRecordingWidget.entitlements"
  sign_adhoc "$bootstrap_installer"
  sign_adhoc "$runtime_worker" --entitlements "$ROOT_DIR/GetOudioAMRuntimeWorker/GetOudioAMRuntimeWorker.entitlements"
  sign_adhoc "$APP_BUNDLE" --entitlements "$ENTITLEMENTS_DIR/GetOudio.entitlements"
}

verify_adhoc_signature() {
  local bundle_path="$1"
  local signature
  local team_identifier
  signature="$(/usr/bin/codesign -dvvv "$bundle_path" 2>&1 | /usr/bin/awk -F= '/^Signature=/{print $2; exit}')"
  team_identifier="$(/usr/bin/codesign -dvvv "$bundle_path" 2>&1 | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"

  if [[ "$signature" != "adhoc" || "$team_identifier" != "not set" ]]; then
    echo "expected an ad-hoc signature without a team: $bundle_path" >&2
    exit 1
  fi
}

verify_v2_entitlements() {
  local bundle_path="$1"
  local entitlements
  entitlements="$(/usr/bin/codesign -d --entitlements :- "$bundle_path" 2>/dev/null)"

  if /usr/bin/grep -q 'com.apple.security.application-groups' <<<"$entitlements"; then
    echo "legacy App Group entitlement remains in $bundle_path" >&2
    exit 1
  fi

  if ! /usr/bin/grep -q "$AGENT_SERVICE_NAME" <<<"$entitlements"; then
    echo "missing background agent mach lookup entitlement in $bundle_path" >&2
    exit 1
  fi

  if /usr/bin/grep -qE 'com\.apple\.application-identifier|com\.apple\.developer\.team-identifier' <<<"$entitlements"; then
    echo "development-only entitlement found in distribution bundle: $bundle_path" >&2
    exit 1
  fi
}

verify_background_agent_plist() {
  local plist="$APP_BUNDLE/Contents/Resources/LaunchAgents/$AGENT_PLIST_NAME"
  [[ -f "$plist" ]] || { echo "missing background agent plist: $plist" >&2; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$plist")" == "$AGENT_SERVICE_NAME" ]] || {
    echo "wrong background agent label" >&2; exit 1;
  }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :ProcessType' "$plist")" == "Interactive" ]] || {
    echo "background agent must use Interactive process type" >&2; exit 1;
  }
  /usr/libexec/PlistBuddy -c "Print :MachServices:$AGENT_SERVICE_NAME" "$plist" >/dev/null
  local runtime_plist="$APP_BUNDLE/Contents/Resources/LaunchAgents/$RUNTIME_WORKER_PLIST_NAME"
  [[ -f "$runtime_plist" ]] || { echo "missing runtime worker plist: $runtime_plist" >&2; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$runtime_plist")" == "$RUNTIME_WORKER_SERVICE_NAME" ]] || {
    echo "wrong runtime worker label" >&2; exit 1;
  }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :ProcessType' "$runtime_plist")" == "Interactive" ]] || {
    echo "runtime worker must use Interactive process type" >&2; exit 1;
  }
  /usr/libexec/PlistBuddy -c "Print :MachServices:$RUNTIME_WORKER_SERVICE_NAME" "$runtime_plist" >/dev/null
}

verify_bootstrap_installer() {
  local installer="$APP_BUNDLE/Contents/Helpers/$BOOTSTRAP_INSTALLER_NAME.app"
  local entitlements
  [[ -x "$installer/Contents/MacOS/$BOOTSTRAP_INSTALLER_NAME" ]] || {
    echo "missing Bootstrap Installer: $installer" >&2; exit 1;
  }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$installer/Contents/Info.plist")" == "true" ]] || {
    echo "Bootstrap Installer must be an LSUIElement app" >&2; exit 1;
  }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$installer/Contents/Info.plist")" == "getoudio-bootstrap" ]] || {
    echo "Bootstrap Installer URL scheme is missing" >&2; exit 1;
  }
  entitlements="$(/usr/bin/codesign -d --entitlements :- "$installer" 2>/dev/null || true)"
  if /usr/bin/grep -qE 'com.apple.security.app-sandbox|com.apple.security.application-groups' <<<"$entitlements"; then
    echo "Bootstrap Installer must not carry sandbox or App Group entitlements" >&2
    exit 1
  fi
}

verify_runtime_worker() {
  local worker="$APP_BUNDLE/Contents/Helpers/GetOudioAMRuntimeWorker.app"
  local entitlements
  [[ -x "$worker/Contents/MacOS/GetOudioAMRuntimeWorker" ]] || {
    echo "missing Apple Music Runtime Worker: $worker" >&2; exit 1;
  }
  entitlements="$(/usr/bin/codesign -d --entitlements :- "$worker" 2>/dev/null)"
  if /usr/bin/grep -qE 'com.apple.security.app-sandbox|com.apple.security.application-groups' <<<"$entitlements"; then
    echo "runtime worker must not carry sandbox or App Group entitlements" >&2
    exit 1
  fi
  if ! /usr/bin/grep -q 'com.apple.security.virtualization' <<<"$entitlements"; then
    echo "runtime worker is missing virtualization entitlement" >&2
    exit 1
  fi
}

verify_distribution_bundle() {
  local bundle_path
  local signed_bundles=(
    "$APP_BUNDLE"
    "$APP_BUNDLE/Contents/PlugIns/GetOudioFinderExtension.appex"
    "$APP_BUNDLE/Contents/PlugIns/GetOudioShareExtension.appex"
    "$APP_BUNDLE/Contents/PlugIns/GetOudioRecordingWidget.appex"
    "$APP_BUNDLE/Contents/Helpers/$BOOTSTRAP_INSTALLER_NAME.app"
    "$APP_BUNDLE/Contents/Helpers/GetOudioAMRuntimeWorker.app"
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
  )

  if find "$APP_BUNDLE" -name embedded.provisionprofile -print -quit | /usr/bin/grep -q .; then
    echo "distribution bundle must not contain embedded.provisionprofile" >&2
    exit 1
  fi

  if ! /usr/bin/codesign --verify --strict --verbose=2 "$APP_BUNDLE"; then
    echo "invalid code signature in $APP_BUNDLE" >&2
    exit 1
  fi

  for bundle_path in "${signed_bundles[@]}"; do
    if [[ ! -d "$bundle_path" ]]; then
      echo "missing embedded bundle: $bundle_path" >&2
      exit 1
    fi

    verify_adhoc_signature "$bundle_path"
  done

  verify_v2_entitlements "$APP_BUNDLE"
  verify_v2_entitlements "$APP_BUNDLE/Contents/PlugIns/GetOudioFinderExtension.appex"
  verify_v2_entitlements "$APP_BUNDLE/Contents/PlugIns/GetOudioShareExtension.appex"
  verify_v2_entitlements "$APP_BUNDLE/Contents/PlugIns/GetOudioRecordingWidget.appex"
  verify_background_agent_plist
  verify_bootstrap_installer
  verify_runtime_worker
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
  /usr/bin/hdiutil verify "$DMG_OUTPUT"
}

build_app
sign_distribution_bundle
verify_distribution_bundle
create_dmg

echo "DMG written to: $DMG_OUTPUT"
echo "This DMG is ad-hoc signed, contains no development provisioning profile, and is not notarized."
echo "Recipients may need to right-click Open or remove Gatekeeper quarantine:"
echo "  xattr -dr com.apple.quarantine \"/Applications/$APP_NAME.app\""
echo "On first settings launch, Get Oudio installs its LaunchAgents with the bundled Bootstrap Installer."
