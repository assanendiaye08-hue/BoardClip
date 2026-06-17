#!/bin/bash
# Cut a release locally: build the DMG, sign the appcast, and publish a GitHub release.
# Use this until GitHub provides macOS 26 runners (the CI workflow does the same on a tag push).
#
# Usage: Scripts/release.sh vX.Y.Z      (bump AppInfo.version to match first)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TAG="${1:?usage: Scripts/release.sh vX.Y.Z}"
VERSION="${TAG#v}"
REPO="$(grep -Eo 'static let githubRepo = "[^"]+"' Sources/BoardClip/App/AppInfo.swift | sed -E 's/.*"([^"]+)".*/\1/')"
APP_VERSION="$(grep -Eo 'static let version = "[^"]+"' Sources/BoardClip/App/AppInfo.swift | sed -E 's/.*"([^"]+)".*/\1/')"
[ "$VERSION" = "$APP_VERSION" ] || { echo "✗ tag $TAG doesn't match AppInfo.version $APP_VERSION — bump it first"; exit 1; }

echo "▸ Cleaning old DMGs and building release DMG…"
rm -f build/BoardClip-*.dmg
./Scripts/make-dmg.sh release
# Use the exact version-named DMG (never glob+head — that can grab a stale older build).
DMG="$ROOT/build/BoardClip-$VERSION.dmg"
[ -f "$DMG" ] || { echo "✗ expected $DMG not found"; exit 1; }

echo "▸ Generating EdDSA-signed appcast…"
./Scripts/sign-update.sh tools
TOOLS="$ROOT/.build/sparkle-tools/bin"
rm -rf updates && mkdir -p updates
cp "$DMG" updates/
"$TOOLS/generate_appcast" \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  updates/
cp updates/appcast.xml build/appcast.xml

echo "▸ Publishing GitHub release $TAG…"
gh release create "$TAG" "$DMG" build/appcast.xml \
  --title "BoardClip ${TAG#v}" --generate-notes \
  || gh release upload "$TAG" "$DMG" build/appcast.xml --clobber

rm -rf updates
echo "✓ Released $TAG → https://github.com/$REPO/releases/tag/$TAG"
