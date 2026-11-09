#!/usr/bin/env bash
# The Tauri app is notarized during bundling; the signed DMG needs its own ticket.
set -euo pipefail

: "${APPLE_API_KEY_PATH:?Missing Apple notarization API key file}"
: "${APPLE_API_KEY:?Missing Apple notarization API key ID}"
: "${APPLE_API_ISSUER:?Missing Apple notarization issuer ID}"
dmg=${1:?Usage: notarize-dmg.sh path-to-signed-dmg}
report=$(mktemp)
trap 'rm "$report"' EXIT

codesign --verify --strict --verbose=2 "$dmg"
xcrun notarytool submit "$dmg" \
  --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY" \
  --issuer "$APPLE_API_ISSUER" --wait --output-format json > "$report"
python3 - "$report" <<'PY'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as source:
    result = json.load(source)
print('Notarization status:', result.get('status'))
if result.get('status') != 'Accepted':
    raise SystemExit('Apple did not accept the disk image.')
PY
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
