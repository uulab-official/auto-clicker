import unittest
from release_info import select_baseline_asset, validate_versions


class BaselineResolutionTests(unittest.TestCase):
    def test_version_order_is_numeric(self):
        validate_versions('0.1.9', '0.1.10')
        with self.assertRaises(ValueError):
            validate_versions('0.1.10', '0.1.9')
        with self.assertRaises(ValueError):
            validate_versions('0.1.1', '0.1.1')
        with self.assertRaises(ValueError):
            validate_versions('0.1.1', '0.1.3-beta')

    def test_selects_real_platform_asset_without_assuming_filename_prefix(self):
        release = {'tag_name':'v0.1.1', 'draft':False, 'prerelease':False, 'assets':[
            {'name':'Auto.Clicker_0.1.1_amd64.AppImage', 'browser_download_url':'https://github.com/uulab-official/auto-clicker/releases/download/v0.1.1/Auto.Clicker_0.1.1_amd64.AppImage', 'digest':'sha256:' + 'a'*64},
            {'name':'Auto.Clicker_0.1.1_amd64.AppImage.sig', 'browser_download_url':'https://example.invalid/ignored'},
        ]}
        self.assertTrue(select_baseline_asset(release, '0.1.1', '_amd64.AppImage')[0].endswith('.AppImage'))
        with self.assertRaises(ValueError):
            select_baseline_asset(release, '0.1.2', '_amd64.AppImage')
        release['assets'][0]['browser_download_url'] = 'https://example.invalid/forged'
        with self.assertRaises(ValueError):
            select_baseline_asset(release, '0.1.1', '_amd64.AppImage')

    def test_rejects_missing_and_ambiguous_assets_and_drafts(self):
        release = {'tag_name':'v0.1.1', 'draft':False, 'prerelease':False, 'assets':[]}
        with self.assertRaises(ValueError): select_baseline_asset(release, '0.1.1', '_x64.dmg')
        asset = {'name':'a_x64.dmg', 'browser_download_url':'https://github.com/uulab-official/auto-clicker/releases/download/v0.1.1/a_x64.dmg', 'digest':'sha256:' + 'a'*64}
        release['assets'] = [asset, dict(asset)]
        with self.assertRaises(ValueError): select_baseline_asset(release, '0.1.1', '_x64.dmg')
        release['assets'] = [asset]; release['draft'] = True
        with self.assertRaises(ValueError): select_baseline_asset(release, '0.1.1', '_x64.dmg')


if __name__ == '__main__':
    unittest.main()
