#!/bin/zsh
# Shared identity policy. Source after setting ROOT; fingerprints are public, not keys.
: "${ROOT:?set ROOT before sourcing signing.sh}"
SIGNING_FIELDS=$(python3 - "$ROOT/Configuration/signing.json" <<'CONFIG'
import json, re, sys
config = json.load(open(sys.argv[1]))
assert config['schema'] == 1, 'Unsupported signing configuration'
for key, length in [('certificateSHA1', 40), ('certificateSHA256', 64)]:
    assert re.fullmatch(r'[A-F0-9]{%d}' % length, config[key]), 'Invalid certificate fingerprint'
assert re.fullmatch(r'[A-Za-z0-9.-]+', config['identifier']), 'Invalid signing identifier'
print(config['certificateSHA1'], config['certificateSHA256'], config['identifier'], sep='\n')
CONFIG
) || return 1
SIGNING_FIELDS=("${(@f)SIGNING_FIELDS}")
SIGNING_SHA1="$SIGNING_FIELDS[1]"
SIGNING_SHA256="$SIGNING_FIELDS[2]"
SIGNING_IDENTIFIER="$SIGNING_FIELDS[3]"
# -R requires '=' to treat the argument as an expression rather than a filename.
SIGNING_REQUIREMENT="=identifier \"$SIGNING_IDENTIFIER\" and certificate leaf = H\"$SIGNING_SHA1\""
IDENTITY="${TANGLER_SIGNING_IDENTITY:-$SIGNING_SHA1}"
KEYCHAIN_ARGS=()
[[ -z ${TANGLER_KEYCHAIN:-} ]] || KEYCHAIN_ARGS=(--keychain "$TANGLER_KEYCHAIN")

require_signing_identity() {
  if [[ "$IDENTITY" == '-' ]]; then
    if [[ ${TANGLER_RELEASE_BUILD:-0} == 1 || ${TANGLER_INSTALL_BUILD:-0} == 1 ]]; then
      print -u2 'Install and release builds require the pinned certificate; ad-hoc signing is not allowed.'
      return 1
    fi
    print -u2 'Explicit ad-hoc source verification build; not suitable for preserving update permissions.'
    return 0
  fi
  if [[ "$IDENTITY" != "$SIGNING_SHA1" ]]; then
    print -u2 'Signing identity differs from Configuration/signing.json. Restore the pinned identity; do not generate another certificate.'
    return 1
  fi
  local available
  available=$(security find-identity -v -p codesigning ${TANGLER_KEYCHAIN:+"$TANGLER_KEYCHAIN"}) || return 1
  if ! print -r -- "$available" | grep -qF " $SIGNING_SHA1 "; then
    print -u2 "Pinned signing identity is unavailable: $SIGNING_SHA1. Restore its certificate and private key; there is no ad-hoc fallback."
    return 1
  fi
}

verify_app_signing() {
  codesign --verify --deep --strict -R "$SIGNING_REQUIREMENT" "$1"
}
