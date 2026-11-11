#!/usr/bin/env python3
"""Resolve a single published baseline installer for an isolated upgrade test."""
import hashlib
import json
import os
import subprocess
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse
from urllib.request import Request, urlopen

_VERSION = re.compile(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')
_REPO = 'uulab-official/auto-clicker'


def validate_versions(baseline, target):
    if not _VERSION.fullmatch(baseline) or not _VERSION.fullmatch(target):
        raise ValueError('Baseline and target must be stable MAJOR.MINOR.PATCH versions')
    if tuple(map(int, target.split('.'))) <= tuple(map(int, baseline.split('.'))):
        raise ValueError('Target version must be newer than baseline')


def select_baseline_asset(release, baseline, suffix):
    if release.get('draft') or release.get('prerelease') or release.get('tag_name') != 'v' + baseline:
        raise ValueError('Baseline must be the requested published stable release')
    choices = [a for a in release.get('assets', []) if a.get('name', '').lower().endswith(suffix.lower())]
    if len(choices) != 1:
        raise ValueError(f'Expected one baseline asset ending in {suffix}, found {len(choices)}')
    asset = choices[0]
    url = asset['browser_download_url']
    parts = urlparse(url)
    expected = f'/{_REPO}/releases/download/v{baseline}/'
    if parts.scheme != 'https' or parts.netloc != 'github.com' or not parts.path.startswith(expected) or parts.query or parts.fragment:
        raise ValueError('Baseline asset URL is not from the expected GitHub release')
    if unquote(parts.path.rsplit('/', 1)[-1]) != asset['name']:
        raise ValueError('Baseline asset URL and name differ')
    digest = asset.get('digest') or ''
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
        raise ValueError('Baseline asset has no valid SHA-256 digest')
    return url, digest.removeprefix('sha256:')


def main():
    if len(sys.argv) != 5:
        raise SystemExit('Usage: release_info.py BASELINE TARGET SUFFIX OUTPUT')
    baseline, target, suffix, output = sys.argv[1:]
    validate_versions(baseline, target)
    # Authenticate only the fixed GitHub metadata lookup. Artifact downloads and
    # the actual installed app still use their ordinary public URLs.
    endpoint = f'repos/{_REPO}/releases/tags/v{baseline}'
    if os.environ.get('GH_TOKEN'):
        release = json.loads(subprocess.check_output(['gh', 'api', endpoint], timeout=30))
    else:
        request = Request(f'https://api.github.com/{endpoint}', headers={'User-Agent': 'auto-clicker-release-verification', 'Accept': 'application/vnd.github+json'})
        with urlopen(request, timeout=30) as response:
            release = json.load(response)
    url, expected = select_baseline_asset(release, baseline, suffix)
    target_path = Path(output)
    digest = hashlib.sha256()
    with urlopen(Request(url, headers={'User-Agent': 'auto-clicker-release-verification'}), timeout=120) as response, target_path.open('wb') as out:
        while chunk := response.read(1024 * 1024):
            out.write(chunk)
            digest.update(chunk)
    if digest.hexdigest() != expected:
        target_path.unlink(missing_ok=True)
        raise ValueError('Downloaded baseline does not match GitHub SHA-256')
    print(f'Downloaded published baseline v{baseline} {suffix}; SHA-256 verified', flush=True)


if __name__ == '__main__':
    main()
