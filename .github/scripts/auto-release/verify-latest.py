#!/usr/bin/env python3
"""Wait for GitHub's latest-release view after a single publish mutation."""
import os
import re
import subprocess
import sys
import time

VERSION = re.compile(r'^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
REPOSITORY = re.compile(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')


def version(value):
    match = VERSION.fullmatch(value)
    return tuple(map(int, match.groups())) if match else None


def await_latest(expected, fetch, clock=time.monotonic, sleep=time.sleep, timeout=45, interval=2):
    target = version(expected)
    if target is None:
        raise ValueError('Invalid expected stable release tag')
    deadline = clock() + timeout
    observed = None
    while True:
        remaining = deadline - clock()
        if remaining <= 0:
            raise RuntimeError(f'{expected} is already published but GitHub latest could not be confirmed (last observed: {observed or "unavailable"})')
        try:
            observed = fetch(min(5, remaining))
        except (OSError, subprocess.SubprocessError):
            observed = None
        if observed == expected:
            return
        newer = version(observed or '')
        if newer is not None and newer > target:
            raise RuntimeError(f'{expected} is already published, but newer release {observed} is latest')
        remaining = deadline - clock()
        if remaining > 0:
            sleep(min(interval, remaining))


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: verify-latest.py RELEASE_TAG')
    repository = os.environ.get('GITHUB_REPOSITORY', '')
    if not REPOSITORY.fullmatch(repository):
        raise ValueError('Invalid GitHub repository')

    def fetch(timeout):
        result = subprocess.run(['gh', 'api', f'repos/{repository}/releases/latest', '--jq', '.tag_name'],
                                check=True, text=True, capture_output=True, timeout=timeout)
        return result.stdout.strip()

    await_latest(sys.argv[1], fetch)
    print(f'GitHub latest confirmed: {sys.argv[1]}')


if __name__ == '__main__':
    main()
