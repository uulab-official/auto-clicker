#!/usr/bin/env python3
"""Validate every updater artifact in a draft GitHub release before publication."""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import quote


def resolve_asset(url, assets, repository, tag):
    """Resolve only an exact draft asset API URL or its canonical public URL."""
    matches = []
    for asset in assets:
        api = f'https://api.github.com/repos/{repository}/releases/assets/{asset["id"]}'
        public = f'https://github.com/{repository}/releases/download/{tag}/{quote(asset["name"], safe="")}'
        draft_public = re.compile(
            rf'https://github\.com/{re.escape(repository)}/releases/download/'
            rf'untagged-[0-9a-f]{{20}}/{re.escape(quote(asset["name"], safe=""))}'
        )
        metadata_url = asset.get('browser_download_url', '')
        if metadata_url != public and not draft_public.fullmatch(metadata_url):
            raise ValueError('Draft asset has an unexpected public download URL')
        if url == api or url == public:
            matches.append((asset, api, public))
    if len(matches) != 1:
        raise ValueError('URL is not exactly one asset in this draft')
    return matches[0]


def main():
    repository = os.environ['GH_REPO']
    tag = os.environ.get('RELEASE_TAG') or os.environ['GITHUB_REF_NAME']
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('A stable version tag is required')
    config = json.loads(Path(os.environ.get('RELEASE_CONFIG_PATH', 'src-tauri/tauri.conf.json')).read_text())
    manifest = json.loads(Path(sys.argv[1]).read_text())
    if manifest['version'] != tag[1:] or config['version'] != tag[1:]:
        raise ValueError('Updater, app and tag versions must match')
    # GitHub's releases/tags endpoint does not resolve unpublished drafts.
    # Resolve the draft with gh, then retrieve its assets by release ID.
    release_id = json.loads(subprocess.check_output([
        'gh', 'release', 'view', tag, '--repo', repository, '--json', 'databaseId'
    ]))['databaseId']
    release = json.loads(subprocess.check_output([
        'gh', 'api', f'repos/{repository}/releases/{release_id}'
    ]))
    if not release.get('draft') or release.get('tag_name') != tag:
        raise ValueError('Release must remain the matching draft during verification')
    expected = ('darwin-aarch64', 'darwin-x86_64', 'linux-x86_64', 'windows-x86_64')
    missing = set(expected) - set(manifest['platforms'])
    if missing:
        raise ValueError(f'Missing required platforms: {sorted(missing)}')
    with tempfile.TemporaryDirectory(prefix='verify-updater-') as tmp:
        tmp = Path(tmp)
        public_key = config['plugins']['updater']['pubkey']
        base64.b64decode(public_key, validate=True)
        verifier = Path('.github/scripts/updater-verify/target/debug/updater-verify').resolve()
        if not verifier.is_file():
            raise ValueError('Build the updater verifier before verifying the release')
        # Bundle-specific keys take precedence in Tauri, so every advertised
        # entry must be authenticated, not only the four generic fallbacks.
        for platform, artifact in manifest['platforms'].items():
            try:
                _, api_url, _ = resolve_asset(artifact['url'], release['assets'], repository, tag)
            except ValueError as exc:
                raise ValueError(f'{platform}: {exc}') from exc
            sig_text = base64.b64decode(artifact['signature'], validate=True).decode('utf-8')
            comments = [line for line in sig_text.splitlines() if line.startswith('trusted comment:')]
            if len(comments) != 1 or f'version:{manifest["version"]}' not in comments[0].split():
                raise ValueError(f'{platform}: signature is not bound to the release version')
            signature = tmp / f'{platform}.sig'
            binary = tmp / platform
            signature.write_text(artifact['signature'].strip())
            with binary.open('wb') as output:
                subprocess.run(['gh', 'api', '-H', 'Accept: application/octet-stream', api_url], stdout=output, check=True)
            verifier_env = dict(os.environ, UPDATER_PUBLIC_KEY=public_key, UPDATER_VERSION=manifest['version'])
            subprocess.run([str(verifier), str(signature)], env=verifier_env, check=True)
            print(f'{platform}: signature and version verified', flush=True)


if __name__ == '__main__':
    main()
