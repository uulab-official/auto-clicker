import base64
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / 'verify-release.py'
spec = importlib.util.spec_from_file_location('verify_release', SCRIPT)
verify_release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify_release)


class VerifyReleaseTest(unittest.TestCase):
    def test_checks_every_platform_including_bundle_specific_entries(self):
        self.assertEqual(self.run_verification(), 6)

    def test_rejects_bundle_specific_entry_outside_draft(self):
        with self.assertRaisesRegex(ValueError, 'windows-x86_64-nsis'):
            self.run_verification(bad_extra=True)

    def test_rejects_missing_required_platform(self):
        with self.assertRaisesRegex(ValueError, 'Missing required platforms'):
            self.run_verification(missing=True)

    def test_rejects_wrong_version_on_bundle_specific_signature(self):
        with self.assertRaisesRegex(ValueError, 'windows-x86_64-nsis'):
            self.run_verification(bad_version=True)

    def test_explicit_release_tag_takes_precedence_for_reusable_workflow(self):
        with mock.patch.dict(os.environ, {'RELEASE_TAG': 'v0.1.2'}):
            self.assertEqual(self.run_verification(ref_name='main'), 6)

    def run_verification(self, bad_extra=False, missing=False, bad_version=False, ref_name='v0.1.2'):
        keys = ['darwin-aarch64', 'darwin-x86_64', 'linux-x86_64', 'windows-x86_64',
                'windows-x86_64-nsis', 'linux-x86_64-deb']
        signature = base64.b64encode(b'trusted comment: version:0.1.2\n').decode()
        platforms = {k: {'url': f'https://api.github.com/repos/owner/repo/releases/assets/{i}',
                         'signature': signature} for i, k in enumerate(keys, 1)}
        if bad_extra:
            platforms['windows-x86_64-nsis']['url'] = 'https://example.com/not-a-draft-asset'
        if missing:
            del platforms['linux-x86_64']
        if bad_version:
            platforms['windows-x86_64-nsis']['signature'] = base64.b64encode(b'trusted comment: version:0.1.1\n').decode()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / 'config.json'
            manifest = root / 'latest.json'
            config.write_text(json.dumps({'version': '0.1.2', 'plugins': {'updater': {'pubkey': base64.b64encode(b'key').decode()}}}))
            manifest.write_text(json.dumps({'version': '0.1.2', 'platforms': platforms}))
            responses = [json.dumps({'databaseId': 3}).encode(),
                         json.dumps({'draft': True, 'assets': [
                             {'id': i, 'name': f'asset{i}',
                              'browser_download_url': f'https://github.com/owner/repo/releases/download/v0.1.2/asset{i}'}
                             for i in range(1, 7)]}).encode()]
            with mock.patch.dict(os.environ, {'GH_REPO': 'owner/repo', 'GITHUB_REF_NAME': ref_name,
                                             'RELEASE_CONFIG_PATH': str(config)}), \
                 mock.patch.object(sys, 'argv', ['verify-release.py', str(manifest)]), \
                 mock.patch.object(Path, 'is_file', return_value=True), \
                 mock.patch.object(verify_release.subprocess, 'check_output', side_effect=responses), \
                 mock.patch.object(verify_release.subprocess, 'run') as run:
                verify_release.main()
            return sum(1 for call in run.call_args_list if call.args[0][0].endswith('updater-verify'))


if __name__ == '__main__':
    unittest.main()
