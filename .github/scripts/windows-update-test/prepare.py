"""Prepare isolated test-only Tauri settings and instrumentation on a CI runner."""
import base64
import json
import os
from pathlib import Path
import secrets
import subprocess

root = Path.cwd()
tmp = Path(os.environ['RUNNER_TEMP']) / 'auto-clicker-update-test'
tmp.mkdir(parents=True, exist_ok=True)
key = tmp / 'updater.key'
password = secrets.token_urlsafe(32)
subprocess.run([str(root / 'node_modules/.bin/tauri.cmd'), 'signer', 'generate', '--ci', '-p', password, '-w', str(key)], check=True, stdout=subprocess.DEVNULL)
(tmp / 'key.env').write_text('TAURI_SIGNING_PRIVATE_KEY=' + key.read_text().strip() + '\nTAURI_SIGNING_PRIVATE_KEY_PASSWORD=' + password + '\n')
pubkey = key.with_suffix('.key.pub').read_text().strip()
base = {'version': '0.1.0', 'plugins': {'updater': {'pubkey': pubkey, 'endpoints': ['http://127.0.0.1:18173/latest.json'], 'dangerousInsecureTransportProtocol': True, 'windows': {'installMode': 'quiet'}}}}
(tmp / 'baseline.json').write_text(json.dumps(base))
(tmp / 'candidate.json').write_text(json.dumps({'version': '0.1.1', 'bundle': {'createUpdaterArtifacts': True}}))
print('Prepared temporary test key and isolated updater settings')
