#!/usr/bin/env python3
"""Reject local build paths and private material in a staged or mounted release artifact."""
import argparse
import os
from pathlib import Path
import re
import sys
import subprocess

# Sparkle's installer uses this generic runtime mkstemp template, not a build path.
PATH_PATTERN = re.compile(
    r"/(?:Users|home|Volumes)/|/(?:private/)?var/(?:folders|root)/"
    r"|/(?:private/)?tmp/(?!XXXXXX\.png(?:\x00|$))"
)
KEY_PATTERN = re.compile(r"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----")
FORBIDDEN_SUFFIXES = {'.p12', '.pfx', '.private-key', '.keychain', '.keychain-db',
                      '.dSYM', '.swiftmodule', '.swiftinterface'}


def inspect_bytes(data, forbidden_prefixes):
    """Inspect text and binary strings without returning any sensitive matched value."""
    reasons = set()
    # Odd offsets cover UTF-16 strings embedded at either alignment in Mach-O/plist data.
    for encoding, offset in [('utf-8', 0), ('utf-16-le', 0), ('utf-16-le', 1),
                             ('utf-16-be', 0), ('utf-16-be', 1)]:
        text = data[offset:].decode(encoding, errors='replace')
        if PATH_PATTERN.search(text):
            reasons.add('local home, volume or temporary path')
        if KEY_PATTERN.search(text):
            reasons.add('private key material')
        if any(prefix in text for prefix in forbidden_prefixes):
            reasons.add('current build-machine path')
    return reasons


def extended_attributes(path):
    # macOS's system Python does not expose os.listxattr/getxattr.
    names = subprocess.run(['/usr/bin/xattr', '-s', str(path)], check=True,
                           capture_output=True, text=True).stdout.splitlines()
    for name in names:
        result = subprocess.run(['/usr/bin/xattr', '-s', '-px', name, str(path)],
                                check=True, capture_output=True, text=True)
        yield bytes.fromhex(result.stdout)


def inspect_artifact(root, forbidden_prefixes=()):
    """Scan every file, link target and extended attribute; never follow external links."""
    root = Path(root)
    if not root.exists() or root.is_symlink():
        raise ValueError('Expected an existing regular artifact or directory')
    base = root if root.is_dir() else root.parent
    entries = [root, *root.rglob('*')] if root.is_dir() else [root]
    findings, files = [], 0
    for path in entries:
        label = str(path.relative_to(base))
        reasons = set()
        if path.name in {'.git', '.DS_Store'} or path.suffix in FORBIDDEN_SUFFIXES:
            reasons.add('development or private file')
        if path.is_symlink():
            target = os.readlink(path)
            # The DMG's standard Applications shortcut is intentionally outside its volume.
            applications_link = path == root / 'Applications' and target == '/Applications'
            if not applications_link:
                if not path.resolve().is_relative_to(base.resolve()):
                    reasons.add('external bundle link')
                reasons.update(inspect_bytes(os.fsencode(target), forbidden_prefixes))
        elif path.is_file():
            files += 1
            reasons.update(inspect_bytes(path.read_bytes(), forbidden_prefixes))
        reasons.update(inspect_bytes(os.fsencode(label), forbidden_prefixes))
        for value in extended_attributes(path):
            if inspect_bytes(value, forbidden_prefixes):
                reasons.add('private data in extended attributes')
        if reasons:
            findings.append({'file': label, 'reasons': sorted(reasons)})
    return files, findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path)
    args = parser.parse_args()
    prefixes = [str(Path(__file__).resolve().parents[1]), str(Path.home())]
    if os.environ.get('TANGLER_BUILD_ROOT'):
        prefixes.append(str(Path(os.environ['TANGLER_BUILD_ROOT']).resolve()))
    try:
        count, findings = inspect_artifact(args.artifact, prefixes)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        # Avoid echoing an exception that could itself contain a developer path.
        print(f'Package privacy check could not complete ({type(error).__name__}).', file=sys.stderr)
        return 1
    if findings:
        for finding in findings:
            print(f"Privacy check failed in {finding['file']}: {', '.join(finding['reasons'])}", file=sys.stderr)
        return 1
    print(f'Package privacy check passed: {count} files plus links and extended attributes.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
