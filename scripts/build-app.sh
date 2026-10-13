#!/bin/zsh
# Build a native or universal bundle, embed Sparkle, then sign nested code from the inside out.
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
source "$ROOT/scripts/env.sh"

# Reject a release without a real updater key before doing an expensive build.
python3 - <<'CHECK'
import base64,json,os,re
from pathlib import Path
config=json.loads(Path('Configuration/updates.json').read_text())
assert re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',config['repository']), 'Invalid GitHub repository'
key=os.environ.get('TANGLER_UPDATE_PUBLIC_KEY',config['publicKey']).strip()
if key:
    assert len(base64.b64decode(key,validate=True))==32, 'Invalid Sparkle public key'
if os.environ.get('TANGLER_RELEASE_BUILD')=='1' and not key:
    raise SystemExit('Release requires an update signing public key in Configuration/updates.json')
CHECK

ARCHS=(${=TANGLER_ARCHS:-$(uname -m)})
BINARIES=()
for arch in "${ARCHS[@]}"; do
  [[ "$arch" == arm64 || "$arch" == x86_64 ]] || { print -u2 "Unsupported architecture: $arch"; exit 1; }
  swift build -c release "${SWIFTPM_PATHS[@]}" --arch "$arch"
  BIN=$(swift build -c release "${SWIFTPM_PATHS[@]}" --arch "$arch" --show-bin-path)
  BINARIES+=("$BIN/Tangler")
done

APP="$ROOT/build/Tangler.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/Tangler-LICENSE.txt"
cp "$ROOT/NOTICE" "$APP/Contents/Resources/Tangler-NOTICE.txt"
cp "$ROOT/Configuration/Branding/Tangler.icns" "$APP/Contents/Resources/Tangler.icns"
# SwiftPM bundles travel with the executable; runtime must not depend on the build cache.
ditto "$BIN/Tangler_CoreKit.bundle" "$APP/Contents/Resources/Tangler_CoreKit.bundle"
for localization in "$ROOT"/Configuration/Localization/*.lproj; do
  ditto "$localization" "$APP/Contents/Resources/${localization:t}"
done
if (( ${#BINARIES} == 1 )); then cp "${BINARIES[1]}" "$APP/Contents/MacOS/Tangler"
else lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Tangler"; fi
SPARKLE="$BUILD_ROOT/artifacts/artifacts/sparkle/Sparkle"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$FRAMEWORK"
cp "$SPARKLE/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
python3 - "$APP/Contents/Info.plist" <<'PLIST'
import json,os,plistlib,re,sys
from pathlib import Path
version=re.search(r'static let version = "([^"]+)"',Path('Sources/App/TanglerMain.swift').read_text()).group(1)
config=json.loads(Path('Configuration/updates.json').read_text())
key=os.environ.get('TANGLER_UPDATE_PUBLIC_KEY',config['publicKey']).strip()
info={
 'CFBundleName':'Tangler','CFBundleDisplayName':'Tangler','CFBundleIdentifier':'app.local.tangler',
 'CFBundleExecutable':'Tangler','CFBundlePackageType':'APPL',
 'CFBundleIconFile':'Tangler.icns',
 'CFBundleDevelopmentRegion':'en','CFBundleLocalizations':['en','zh-Hans'],
 'CFBundleShortVersionString':version,'CFBundleVersion':version,
 'LSMinimumSystemVersion':'26.0','LSUIElement':True,'NSHighResolutionCapable':True,
 'NSScreenCaptureUsageDescription':'Show window thumbnails in the switcher and Dock previews. Images are processed only on this Mac.',
 'SUFeedURL':f"https://github.com/{config['repository']}/releases/latest/download/appcast.xml",
 'SUEnableAutomaticChecks':True,'SUAutomaticallyUpdate':False,'SUScheduledCheckInterval':21600,
 'SUEnableSystemProfiling':False,'SUVerifyUpdateBeforeExtraction':True,'SURequireSignedFeed':True,
}
if key: info['SUPublicEDKey']=key
Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
PLIST
IDENTITY="${TANGLER_SIGNING_IDENTITY:-Tangler Local Signing}"
KEYCHAIN_ARGS=()
if [[ -n ${TANGLER_KEYCHAIN:-} ]]; then KEYCHAIN_ARGS=(--keychain "$TANGLER_KEYCHAIN"); fi
if [[ "$IDENTITY" != '-' ]] && ! security find-identity -v -p codesigning ${TANGLER_KEYCHAIN:-} | grep -qF "\"$IDENTITY\""; then
  if [[ -n ${TANGLER_SIGNING_IDENTITY:-} ]]; then print -u2 "Requested signing identity not found: $IDENTITY"; exit 1; fi
  IDENTITY='-'
fi
SIGN_ARGS=(--force --sign "$IDENTITY" "${KEYCHAIN_ARGS[@]}")
if [[ "$IDENTITY" == 'Developer ID Application:'* ]]; then SIGN_ARGS+=(--options runtime --timestamp); fi
for nested in "$FRAMEWORK"/Versions/B/XPCServices/*.xpc(N) "$FRAMEWORK/Versions/B/Updater.app" "$FRAMEWORK/Versions/B/Autoupdate"; do
  codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$nested"
done
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK"
codesign "${SIGN_ARGS[@]}" --identifier app.local.tangler "$APP"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/Tangler"
print "已生成 $APP（签名：$IDENTITY）"
