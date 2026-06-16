#!/bin/bash
# Create a stable self-signed code-signing identity in a dedicated keychain, so macOS keeps
# Accessibility/Photos permission across rebuilds (ad-hoc signatures change every build and
# re-prompt). Fully headless — no login password, no GUI keychain prompt. Run once.
set -euo pipefail

NAME="${1:-BoardClip Dev}"
KEYCHAIN="$HOME/Library/Keychains/boardclip-signing.keychain-db"
KCPASS="boardclip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "✓ Identity '$NAME' already available."
  exit 0
fi

echo "▸ Creating dedicated signing keychain…"
security create-keychain -p "$KCPASS" "$KEYCHAIN" 2>/dev/null || true
security set-keychain-settings "$KEYCHAIN"               # no auto-lock timeout
security unlock-keychain -p "$KCPASS" "$KEYCHAIN"
# Add to the user search list (keep the existing keychains).
OTHERS="$(security list-keychains -d user | sed -e 's/^[[:space:]]*//' -e 's/"//g' | grep -v 'boardclip-signing' || true)"
security list-keychains -d user -s "$KEYCHAIN" $OTHERS

echo "▸ Generating self-signed code-signing certificate '$NAME'…"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

echo "▸ Importing into keychain…"
# Import the PEM cert + key separately (avoids PKCS#12 cipher incompatibility between
# OpenSSL 3 and macOS's security tool). The matching pair forms a code-signing identity.
security import "$TMP/cert.pem" -k "$KEYCHAIN" -A -T /usr/bin/codesign >/dev/null 2>&1 || true
security import "$TMP/key.pem"  -k "$KEYCHAIN" -A -T /usr/bin/codesign >/dev/null 2>&1 || true
# Let codesign use the key without prompting.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KEYCHAIN" >/dev/null 2>&1 || true

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "✓ Created '$NAME'. Rebuild with: make run"
else
  echo "⚠︎ Identity not visible to codesign yet — try: security unlock-keychain -p $KCPASS \"$KEYCHAIN\""
  exit 1
fi
