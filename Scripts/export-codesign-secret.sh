#!/bin/bash
# Export the stable BoardClip code-signing identity to GitHub Actions secrets.
# Run after Scripts/make-cert.sh. The private key is uploaded to GitHub secrets
# and the temporary PKCS#12 file is deleted before exit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IDENTITY="${1:-BoardClip Dev}"
KEYCHAIN="${BOARDCLIP_SIGN_KEYCHAIN:-$HOME/Library/Keychains/boardclip-signing.keychain-db}"
KEYCHAIN_PASSWORD="${BOARDCLIP_SIGN_KEYCHAIN_PASSWORD:-boardclip}"

command -v gh >/dev/null || { echo "✗ GitHub CLI (gh) is required"; exit 1; }
gh auth status >/dev/null

if ! security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
  echo "✗ Signing identity '$IDENTITY' not found in $KEYCHAIN" >&2
  echo "  Run Scripts/make-cert.sh first." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
P12="$TMP/boardclip-codesign.p12"
P12_PASSWORD="$(openssl rand -hex 24)"

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security export -k "$KEYCHAIN" -t identities -f pkcs12 -P "$P12_PASSWORD" -o "$P12" >/dev/null

/usr/bin/base64 -i "$P12" | gh secret set BOARDCLIP_CODESIGN_P12
printf '%s' "$P12_PASSWORD" | gh secret set BOARDCLIP_CODESIGN_P12_PASSWORD
gh variable set BOARDCLIP_SIGN_IDENTITY --body "$IDENTITY" >/dev/null

echo "✓ Uploaded BOARDCLIP_CODESIGN_P12 and BOARDCLIP_CODESIGN_P12_PASSWORD for '$IDENTITY'."
