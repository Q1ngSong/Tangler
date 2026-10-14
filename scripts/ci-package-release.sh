#!/bin/zsh
# Import the pinned identity only on an ephemeral GitHub runner; clean up on all exits.
set -euo pipefail
set +x
ROOT="${0:A:h:h}"
[[ ${GITHUB_ACTIONS:-} == true && ${RUNNER_ENVIRONMENT:-} == github-hosted ]] || {
  print -u2 'This entry point requires an ephemeral GitHub-hosted runner. Locally, use package-release.sh.'; exit 1
}
: "${RUNNER_TEMP:?Missing RUNNER_TEMP}"
for secret in TANGLER_SIGNING_P12_BASE64 TANGLER_SIGNING_P12_PASSWORD SPARKLE_PRIVATE_KEY; do
  [[ -n ${(P)secret:-} ]] || { print -u2 "Missing repository secret: $secret"; exit 1; }
done
source "$ROOT/scripts/signing.sh"
umask 077
WORK=$(mktemp -d "$RUNNER_TEMP/tangler-signing.XXXXXX")
export TANGLER_KEYCHAIN="$WORK/signing.keychain-db"
TRUST_ADDED=0
KEYCHAIN_CREATED=0
SEARCH_LIST_CHANGED=0
ORIGINAL_KEYCHAINS=()
run_bounded() {
  python3 - "$@" <<'BOUNDED'
import subprocess, sys
try:
    sys.exit(subprocess.run(sys.argv[2:], timeout=int(sys.argv[1])).returncode)
except subprocess.TimeoutExpired:
    print(f'Signing operation timed out: {sys.argv[2]}', file=sys.stderr)
    sys.exit(1)
BOUNDED
}
cleanup() {
  local result=$?
  trap - EXIT HUP INT TERM
  print 'Cleaning up the temporary signing identity.'
  if (( TRUST_ADDED )); then run_bounded 20 sudo -n security remove-trusted-cert -d "$WORK/certificate.pem" || result=1; fi
  if (( SEARCH_LIST_CHANGED )); then run_bounded 20 security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" || result=1; fi
  if (( KEYCHAIN_CREATED )); then run_bounded 20 security delete-keychain "$TANGLER_KEYCHAIN" || result=1; fi
  rm -rf -- "$WORK"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
printf '%s' "$TANGLER_SIGNING_P12_BASE64" | base64 --decode > "$WORK/identity.p12"
# Extract only the public leaf before trusting/importing anything. Password stays out of argv.
if ! openssl pkcs12 -in "$WORK/identity.p12" -passin env:TANGLER_SIGNING_P12_PASSWORD \
  -clcerts -nokeys -out "$WORK/certificate.pem"; then
  # Keychain Access may export legacy PKCS#12 encryption unsupported by OpenSSL 3 defaults.
  openssl pkcs12 -legacy -in "$WORK/identity.p12" -passin env:TANGLER_SIGNING_P12_PASSWORD \
    -clcerts -nokeys -out "$WORK/certificate.pem"
fi
FINGERPRINT=$(openssl x509 -in "$WORK/certificate.pem" -noout -fingerprint -sha256)
FINGERPRINT="${${FINGERPRINT#*=}//:/}"
[[ "$FINGERPRINT" == "$SIGNING_SHA256" ]] || { print -u2 'Signing certificate does not match the pinned SHA-256 fingerprint.'; exit 1; }
print 'Pinned certificate verified; configuring the temporary signing keychain.'
# codesign needs the identity's keychain in the search list even with --keychain.
# Parse security's quoted paths without splitting keychain names containing spaces.
ORIGINAL_KEYCHAINS=("${(@f)$(security list-keychains -d user | python3 -c 'import shlex, sys; print("\n".join(shlex.split(sys.stdin.read())))')}")
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
print "::add-mask::$KEYCHAIN_PASSWORD"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$TANGLER_KEYCHAIN"
KEYCHAIN_CREATED=1
security set-keychain-settings -lut 21600 "$TANGLER_KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$TANGLER_KEYCHAIN"
SEARCH_LIST_CHANGED=1
security list-keychains -d user -s "$TANGLER_KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}"
security import "$WORK/identity.p12" -P "$TANGLER_SIGNING_P12_PASSWORD" \
  -t cert -f pkcs12 -k "$TANGLER_KEYCHAIN" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$TANGLER_KEYCHAIN" >/dev/null
# This trust is scoped to code signing on the disposable runner and removed on exit.
TRUST_ADDED=1
sudo -n security add-trusted-cert -d -r trustRoot -p codeSign -k "$TANGLER_KEYCHAIN" "$WORK/certificate.pem"
export TANGLER_SIGNING_IDENTITY="$SIGNING_SHA1"
export SPARKLE_PRIVATE_KEY_FILE="$WORK/sparkle.private-key"
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$SPARKLE_PRIVATE_KEY_FILE"
unset TANGLER_SIGNING_P12_BASE64 TANGLER_SIGNING_P12_PASSWORD SPARKLE_PRIVATE_KEY KEYCHAIN_PASSWORD
require_signing_identity || exit 1
print 'Checking actual signing before compiling the App.'
cp /usr/bin/true "$WORK/signing-probe"
run_bounded 30 codesign --force --sign "$SIGNING_SHA1" --keychain "$TANGLER_KEYCHAIN" \
  --identifier "$SIGNING_IDENTIFIER" "$WORK/signing-probe" || exit $?
codesign --verify --strict -R "$SIGNING_REQUIREMENT" "$WORK/signing-probe"
print 'Signing preflight passed; building the universal release.'
"$ROOT/scripts/package-release.sh"
