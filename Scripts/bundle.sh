#!/bin/bash
# Assemble BoardClip.app from a SwiftPM build, embedding Sparkle.
# Usage: Scripts/bundle.sh [debug|release]
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="BoardClip"
APP="$ROOT/build/$APP_NAME.app"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Version from AppInfo.swift.
VERSION="$(grep -Eo 'static let version = "[^"]+"' Sources/BoardClip/App/AppInfo.swift | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
if [ -z "${VERSION:-}" ]; then
  echo "✗ Could not read AppInfo.version" >&2
  exit 1
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"

# Monotonic build number. Sparkle compares CFBundleVersion when deciding whether an
# update is newer. Derive it from the marketing version instead of git history so
# shallow CI checkouts cannot accidentally publish build 1 for every release.
build_number_from_version() {
  local major minor patch rest
  IFS=. read -r major minor patch rest <<< "$1"
  major="${major:-0}"
  minor="${minor:-0}"
  patch="${patch:-0}"

  if [ -n "${rest:-}" ] || [[ ! "$major" =~ ^[0-9]+$ ]] || [[ ! "$minor" =~ ^[0-9]+$ ]] || [[ ! "$patch" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  local build
  build=$((10#$major * 1000000 + 10#$minor * 1000 + 10#$patch))
  [ "$build" -ge 1 ] || return 1
  printf '%d\n' "$build"
}

if [ -n "${BOARDCLIP_BUILD_NUMBER:-}" ]; then
  if [[ ! "$BOARDCLIP_BUILD_NUMBER" =~ ^[0-9]+$ ]] || [ "$BOARDCLIP_BUILD_NUMBER" -lt 1 ]; then
    echo "✗ BOARDCLIP_BUILD_NUMBER must be a positive integer" >&2
    exit 1
  fi
  BUILD="$BOARDCLIP_BUILD_NUMBER"
else
  BUILD="$(build_number_from_version "$VERSION")" || {
    echo "✗ AppInfo.version must be numeric major.minor.patch, got: $VERSION" >&2
    exit 1
  }
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

# Derive the update feed from AppInfo.githubRepo (single source of truth).
REPO="$(grep -Eo 'static let githubRepo = "[^"]+"' Sources/BoardClip/App/AppInfo.swift | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
[ -n "${REPO:-}" ] && /usr/libexec/PlistBuddy -c "Set :SUFeedURL https://github.com/$REPO/releases/latest/download/appcast.xml" "$APP/Contents/Info.plist" 2>/dev/null || true

[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# --- Embed Sparkle.framework ---
SPARKLE_SRC="$BIN_DIR/Sparkle.framework"
if [ -d "$SPARKLE_SRC" ]; then
  echo "▸ Embedding Sparkle.framework"
  cp -R "$SPARKLE_SRC" "$APP/Contents/Frameworks/"
  # Ensure the executable can find embedded frameworks.
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
else
  echo "⚠︎ Sparkle.framework not found at $SPARKLE_SRC (auto-update will be disabled)"
fi

# --- Sign inside-out ---
IDENTITY="${BOARDCLIP_SIGN_IDENTITY:-BoardClip Dev}"
# No -v: a self-signed dev cert is untrusted (filtered by -v) but still signs fine and gives a
# stable designated requirement, so macOS keeps Accessibility/Photos permission across rebuilds.
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  SIGN_ID="$IDENTITY"; echo "▸ Signing with identity: $IDENTITY"
else
  SIGN_ID="-"; echo "▸ Signing ad-hoc (run Scripts/make-cert.sh for a stable identity)"
fi

ENTITLEMENTS="$ROOT/Resources/BoardClip.entitlements"
sign() { codesign --force --options runtime --timestamp=none --sign "$SIGN_ID" "$1"; }

SPK="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPK" ]; then
  VB="$SPK/Versions/B"
  for xpc in "$VB/XPCServices/"*.xpc; do [ -e "$xpc" ] && sign "$xpc"; done
  [ -e "$VB/Autoupdate" ] && sign "$VB/Autoupdate"
  [ -e "$VB/Updater.app" ] && sign "$VB/Updater.app"
  sign "$SPK"
fi
# The main app needs disable-library-validation to load the (differently-signed) framework.
codesign --force --options runtime --timestamp=none \
  --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$APP"

echo "✓ Built $APP ($VERSION, signed: $SIGN_ID)"
