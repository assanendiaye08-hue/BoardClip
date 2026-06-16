#!/bin/bash
# Sparkle EdDSA helpers.
#   Scripts/sign-update.sh keygen          -> create signing keys, print SUPublicEDKey
#   Scripts/sign-update.sh sign <file>     -> print the ed signature for an update file
#
# The Sparkle CLI tools (generate_keys / sign_update / generate_appcast) are downloaded
# on demand from the Sparkle release that SwiftPM resolved.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.build/sparkle-tools"
SPARKLE_VERSION="2.9.3"

ensure_tools() {
  if [ -x "$TOOLS/bin/sign_update" ]; then return; fi
  echo "▸ Fetching Sparkle $SPARKLE_VERSION CLI tools…" >&2
  mkdir -p "$TOOLS"
  local url="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  curl -fsSL "$url" | tar -xJ -C "$TOOLS"
}

ensure_tools
CMD="${1:-}"
case "$CMD" in
  keygen)
    "$TOOLS/bin/generate_keys"
    echo
    echo "Public key above → put it in Resources/Info.plist under SUPublicEDKey."
    echo "Export the private key for CI with: Scripts/sign-update.sh export"
    ;;
  export)
    OUT="${2:-$ROOT/sparkle_ed_private_key.private}"
    "$TOOLS/bin/generate_keys" -x "$OUT"
    echo "▸ Private key written to: $OUT"
    echo "  Paste its contents into the GitHub secret SPARKLE_ED_PRIVATE_KEY, then delete the file."
    ;;
  sign)
    [ -n "${2:-}" ] || { echo "usage: sign-update.sh sign <file>"; exit 1; }
    "$TOOLS/bin/sign_update" "$2"
    ;;
  tools)
    echo "✓ Sparkle CLI tools ready at $TOOLS/bin" ;;
  *)
    echo "usage: sign-update.sh {keygen|export|sign <file>|tools}"; exit 1 ;;
esac
