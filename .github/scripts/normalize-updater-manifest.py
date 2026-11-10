#!/usr/bin/env python3
"""Replace draft updater API asset URLs with canonical public download URLs."""
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys

spec = importlib.util.spec_from_file_location('verify_release', Path(__file__).with_name('verify-release.py'))
verify_release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify_release)


def normalize(manifest, release, repository, tag):
    if not release.get('draft') or release.get('tag_name') != tag:
        raise ValueError('Expected matching draft release')
    if manifest['version'] != tag[1:]:
        raise ValueError('Updater version does not match tag')
    for artifact in manifest['platforms'].values():
        _, _, public = verify_release.resolve_asset(artifact['url'], release['assets'], repository, tag)
        artifact['url'] = public
    return manifest


def main():
    repository = os.environ['GH_REPO']
    tag = os.environ.get('RELEASE_TAG') or os.environ['GITHUB_REF_NAME']
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('A stable version tag is required')
    release_id = json.loads(subprocess.check_output(['gh', 'release', 'view', tag, '--repo', repository, '--json', 'databaseId']))['databaseId']
    release = json.loads(subprocess.check_output(['gh', 'api', f'repos/{repository}/releases/{release_id}']))
    path = Path(sys.argv[1])
    manifest = normalize(json.loads(path.read_text()), release, repository, tag)
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
