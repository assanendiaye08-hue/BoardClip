#!/bin/bash
# Build and run tests while embedding Sparkle in the XCTest bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build --build-tests --disable-automatic-resolution
BIN_DIR="$(swift build --disable-automatic-resolution --show-bin-path)"
TEST_BUNDLE="$BIN_DIR/BoardClipTests.xctest"
SPARKLE="$BIN_DIR/Sparkle.framework"

if [ ! -d "$TEST_BUNDLE" ] || [ ! -d "$SPARKLE" ]; then
  echo "Could not locate the BoardClip test bundle or Sparkle.framework" >&2
  exit 1
fi

mkdir -p "$TEST_BUNDLE/Contents/Frameworks"
rm -rf "$TEST_BUNDLE/Contents/Frameworks/Sparkle.framework"
cp -R "$SPARKLE" "$TEST_BUNDLE/Contents/Frameworks/"

swift test --skip-build
