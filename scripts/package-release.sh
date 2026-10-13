#!/bin/zsh
# One signed DMG serves both first installs and Sparkle updates. This script never uploads.
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
source "$ROOT/scripts/env.sh"
export TANGLER_RELEASE_BUILD=1
export TANGLER_ARCHS="${TANGLER_ARCHS:-arm64 x86_64}"
[[ -n ${SPARKLE_PRIVATE_KEY_FILE:-} && -f "$SPARKLE_PRIVATE_KEY_FILE" ]] || { print -u2 'Set SPARKLE_PRIVATE_KEY_FILE to the exported Sparkle key outside Git.'; exit 1; }
./scripts/build-app.sh
APP="$ROOT/build/Tangler.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
REPO=$(python3 -c 'import json; print(json.load(open("Configuration/updates.json"))["repository"])')
if [[ -n ${GITHUB_REF_NAME:-} && ${GITHUB_REF_TYPE:-} == tag && "$GITHUB_REF_NAME" != "v$VERSION" ]]; then
  print -u2 'Tag and app version disagree'; exit 1
fi
OUT="${TANGLER_RELEASE_OUTPUT:-$ROOT/build/release}"
mkdir -p "$OUT"
[[ -z "$(ls -A "$OUT")" ]] || { print -u2 "Output directory must be empty: $OUT"; exit 1; }
WORK=$(mktemp -d "$ROOT/build/package.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
codesign --verify --deep --strict --verbose=2 "$APP"
# Assessment is diagnostic: self-signed/ad-hoc bundles are not notarized distributions.
spctl -a -vv "$APP" || true
xattr -lr "$APP"
ditto "$APP" "$WORK/Tangler.app"
xattr -cr "$WORK/Tangler.app"
ln -s /Applications "$WORK/Applications"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/Tangler")
if [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]]; then SUFFIX=universal
else SUFFIX="$ARCHS"; fi
DMG="$OUT/Tangler_${VERSION}_${SUFFIX}.dmg"
hdiutil create -volname Tangler -srcfolder "$WORK" -format UDZO "$DMG"
TOOLS="$BUILD_ROOT/artifacts/artifacts/sparkle/Sparkle/bin"
"$TOOLS/generate_appcast" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --link "https://github.com/$REPO" --maximum-deltas 0 "$OUT"
"$TOOLS/sign_update" --verify --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" "$OUT/appcast.xml"
SIGNATURE=$(python3 - "$OUT/appcast.xml" "$VERSION" "$DMG" <<'CAST'
from pathlib import Path
import sys,xml.etree.ElementTree as ET
root=ET.parse(sys.argv[1]).getroot(); item=root.find('./channel/item')
ns={'s':'http://www.andymatuschak.org/xml-namespaces/sparkle'}
assert item is not None and item.findtext('s:version',namespaces=ns)==sys.argv[2], 'Appcast version mismatch'
enclosure=item.find('enclosure')
assert enclosure is not None
assert int(enclosure.attrib['length'])==Path(sys.argv[3]).stat().st_size
assert enclosure.attrib['url'].endswith('/'+Path(sys.argv[3]).name)
# generate_appcast omits this signature if the private key does not match the app public key.
signature=enclosure.attrib.get('{'+ns['s']+'}edSignature')
assert signature, 'Update signature missing: verify that SPARKLE_PRIVATE_KEY matches the app public key'
print(signature)
CAST
)
"$TOOLS/sign_update" --verify --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" "$DMG" "$SIGNATURE"
(cd "$OUT" && shasum -a 256 *.dmg appcast.xml > SHA256SUMS)
print "本地发布文件已生成并验证：$OUT（没有上传）"
