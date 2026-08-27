#!/usr/bin/env bash
set -euo pipefail

# Runs after embedding and before Xcode signs the outer App. Never modifies
# the source ThirdParty directory or the cached Sparkle package.
APP_BUNDLE="${1:?usage: prepare_bundle_architecture.sh <app> <architecture>}"
TARGET_ARCH="${2:?missing architecture}"
SPARKLE_FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/B"

case "$TARGET_ARCH" in
  arm64|x86_64) ;;
  *) echo "expected one architecture (arm64 or x86_64), got: $TARGET_ARCH" >&2; exit 1 ;;
esac
[[ -d "$APP_BUNDLE/Contents/MacOS" ]] || { echo "invalid app bundle: $APP_BUNDLE" >&2; exit 1; }

# Preflight every Mach-O before changing anything. Source-built code and
# bundled tools must already match; only the prebuilt Sparkle framework is thinned.
sparkle_needs_thinning=false
binary_count=0
while IFS= read -r -d '' binary; do
  [[ "$(/usr/bin/file -b "$binary")" == *Mach-O* ]] || continue
  binary_count=$((binary_count + 1))
  if ! /usr/bin/lipo "$binary" -verify_arch "$TARGET_ARCH"; then
    echo "missing $TARGET_ARCH architecture: $binary" >&2
    exit 1
  fi
  if [[ "$(/usr/bin/lipo -archs "$binary")" != "$TARGET_ARCH" ]]; then
    if [[ "$binary" == "$SPARKLE_FRAMEWORK/"* ]]; then
      sparkle_needs_thinning=true
    else
      echo "expected only $TARGET_ARCH architecture: $binary" >&2
      exit 1
    fi
  fi
done < <(/usr/bin/find "$APP_BUNDLE" -type f -print0)
[[ "$binary_count" -gt 0 ]] || { echo "no Mach-O binaries found: $APP_BUNDLE" >&2; exit 1; }

if [[ "$sparkle_needs_thinning" == true ]]; then
  while IFS= read -r -d '' binary; do
    [[ "$(/usr/bin/file -b "$binary")" == *Mach-O* ]] || continue
    if [[ "$(/usr/bin/lipo -archs "$binary")" != "$TARGET_ARCH" ]]; then
      /usr/bin/lipo "$binary" -thin "$TARGET_ARCH" -output "$binary"
    fi
  done < <(/usr/bin/find "$SPARKLE_FRAMEWORK" -type f -print0)

  # Re-sign from the inside out, preserving Sparkle's helper entitlements and
  # hardened-runtime flags. Unsigned builds use ad-hoc signatures until packaging.
  for code in \
    "$SPARKLE_VERSION/XPCServices/Installer.xpc" \
    "$SPARKLE_VERSION/XPCServices/Downloader.xpc" \
    "$SPARKLE_VERSION/Autoupdate" \
    "$SPARKLE_VERSION/Updater.app" \
    "$SPARKLE_FRAMEWORK"; do
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" \
      --preserve-metadata=identifier,entitlements,flags --timestamp=none "$code"
  done
fi

echo "Verified $binary_count Mach-O binaries for $TARGET_ARCH: $APP_BUNDLE"
