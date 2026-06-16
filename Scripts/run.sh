#!/bin/bash
# Build, bundle and (re)launch BoardClip. Usage: Scripts/run.sh [debug|release]
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/Scripts/bundle.sh" "$CONFIG"

# Relaunch a fresh copy.
osascript -e 'quit app "BoardClip"' >/dev/null 2>&1 || true
pkill -x BoardClip >/dev/null 2>&1 || true
sleep 0.3
open "$ROOT/build/BoardClip.app"
echo "✓ Launched BoardClip (look for the clipboard icon in the menu bar)"
