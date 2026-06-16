#!/bin/bash
# Cut a release locally: build the DMG, sign the appcast, and publish a GitHub release.
# Use this until GitHub provides macOS 26 runners (the CI workflow does the same on a tag push).
#
# Usage: Scripts/release.sh vX.Y.Z      (bump AppInfo.version to match first)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TAG="${1:?usage: Scripts/release.sh vX.Y.Z}"
REPO="$(grep -Eo 'static let githubRepo = "[^"]+"' Sources/BoardClip/App/AppInfo.swift | sed -E 's/.*"([^"]+)".*/\1/')"

echo "▸ Building release DMG…"
./Scripts/make-dmg.sh release
DMG="$(ls build/BoardClip-*.dmg | head -1)"

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
