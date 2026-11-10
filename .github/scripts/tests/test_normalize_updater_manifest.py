import importlib.util
from pathlib import Path
import unittest

script = Path(__file__).resolve().parents[1] / 'normalize-updater-manifest.py'
spec = importlib.util.spec_from_file_location('normalize_updater_manifest', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class NormalizeTest(unittest.TestCase):
    def setUp(self):
        self.repo = 'owner/repo'
        self.tag = 'v0.1.2'
        self.public = 'https://github.com/owner/repo/releases/download/v0.1.2/file%20name.tar.gz'
        self.api = 'https://api.github.com/repos/owner/repo/releases/assets/42'
        self.release = {'draft': True, 'tag_name': self.tag, 'assets': [
            {'id': 42, 'name': 'file name.tar.gz', 'browser_download_url': self.public}]}
        self.manifest = {'version': '0.1.2', 'platforms': {'darwin-aarch64': {'url': self.api, 'signature': 'unchanged'}}}

    def test_normalizes_api_url_and_is_idempotent(self):
        normalized = module.normalize(self.manifest, self.release, self.repo, self.tag)
        self.assertEqual(normalized['platforms']['darwin-aarch64'], {'url': self.public, 'signature': 'unchanged'})
        self.assertEqual(module.normalize(normalized, self.release, self.repo, self.tag), normalized)
        self.assertEqual(module.verify_release.resolve_asset(self.public, self.release['assets'], self.repo, self.tag)[1], self.api)

    def test_rejects_foreign_and_wrong_asset_urls(self):
        for url in ('https://example.com/42', self.public + '?x=1', self.api + '0', self.public.replace('file%20name', 'other')):
            with self.subTest(url=url), self.assertRaises(ValueError):
                module.verify_release.resolve_asset(url, self.release['assets'], self.repo, self.tag)

    def test_rejects_noncanonical_github_metadata(self):
        self.release['assets'][0]['browser_download_url'] = 'https://example.com/file'
        with self.assertRaises(ValueError):
            module.normalize(self.manifest, self.release, self.repo, self.tag)

    def test_actual_github_draft_metadata_generates_tagged_public_url(self):
        # Shape observed in the authenticated v0.1.9 draft response.
        name = 'Auto.Clicker_0.1.9_amd64.AppImage'
        asset = {'id': 123, 'name': name, 'browser_download_url':
                 'https://github.com/uulab-official/auto-clicker/releases/download/'
                 'untagged-c2bd15c18f318180127e/' + name}
        repo, tag = 'uulab-official/auto-clicker', 'v0.1.9'
        api = f'https://api.github.com/repos/{repo}/releases/assets/123'
        public = f'https://github.com/{repo}/releases/download/{tag}/{name}'
        self.assertEqual(module.verify_release.resolve_asset(api, [asset], repo, tag)[2], public)
        self.assertEqual(module.verify_release.resolve_asset(public, [asset], repo, tag)[1], api)
        asset['browser_download_url'] = asset['browser_download_url'].replace('untagged-c2bd15c18f318180127e', 'untagged-evil')
        with self.assertRaises(ValueError):
            module.verify_release.resolve_asset(api, [asset], repo, tag)

    def test_rejects_published_or_wrong_tag(self):
        for field, value in [('draft', False), ('tag_name', 'v0.1.3')]:
            release = dict(self.release, **{field: value})
            with self.subTest(field=field), self.assertRaises(ValueError):
                module.normalize(self.manifest, release, self.repo, self.tag)


if __name__ == '__main__':
    unittest.main()
