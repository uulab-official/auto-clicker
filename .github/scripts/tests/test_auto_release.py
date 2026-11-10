import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'auto-release' / 'version.py'
spec = importlib.util.spec_from_file_location('release_version', SCRIPT)
version = importlib.util.module_from_spec(spec)
spec.loader.exec_module(version)


class AutoReleaseVersionTest(unittest.TestCase):
    def test_skips_existing_tags_and_unpublished_drafts(self):
        self.assertEqual(version.next_version('0.1.5', ['v0.1.4', 'v0.1.5', 'v0.1.7']), '0.1.8')

    def test_preserves_source_release_line_and_ignores_prereleases(self):
        self.assertEqual(version.next_version('0.1.5', ['v0.1.7', 'v9.0.0-rc1']), '0.1.8')
        with self.assertRaisesRegex(ValueError, 'major/minor'):
            version.next_version('0.1.5', ['v1.2.3'])

    def test_msi_limit_and_invalid_current_fail_closed(self):
        for current in ['1.2.65535', '256.0.0', '1.0.0-beta']:
            with self.assertRaises(ValueError):
                version.next_version(current, [])

    def test_updates_five_version_sources_without_touching_other_cargo_packages(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'src-tauri').mkdir()
            (root / 'package.json').write_text('{"version":"0.1.5","name":"test"}')
            (root / 'package-lock.json').write_text('{"version":"0.1.5","packages":{"":{"version":"0.1.5"}}}')
            (root / 'src-tauri/tauri.conf.json').write_text('{"version":"0.1.5"}')
            (root / 'src-tauri/Cargo.toml').write_text('[package]\nname = "auto-clicker"\nversion = "0.1.5"\n')
            (root / 'src-tauri/Cargo.lock').write_text('[[package]]\nname = "other"\nversion = "0.1.5"\n\n[[package]]\nname = "auto-clicker"\nversion = "0.1.5"\n')
            version.set_version(root, '0.1.6')
            for file in ('package.json', 'package-lock.json', 'src-tauri/tauri.conf.json'):
                self.assertEqual(json.loads((root / file).read_text())['version'], '0.1.6')
            self.assertEqual(json.loads((root / 'package-lock.json').read_text())['packages']['']['version'], '0.1.6')
            self.assertIn('name = "other"\nversion = "0.1.5"', (root / 'src-tauri/Cargo.lock').read_text())
            self.assertIn('name = "auto-clicker"\nversion = "0.1.6"', (root / 'src-tauri/Cargo.lock').read_text())

    def test_does_not_write_any_files_if_expected_cargo_entry_is_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'src-tauri').mkdir()
            for file in ('package.json', 'src-tauri/tauri.conf.json'):
                (root / file).write_text('{"version":"0.1.5"}')
            (root / 'package-lock.json').write_text('{"version":"0.1.5","packages":{"":{}}}')
            (root / 'src-tauri/Cargo.toml').write_text('[package]\nversion = "0.1.5"\n')
            (root / 'src-tauri/Cargo.lock').write_text('')
            with self.assertRaises(ValueError):
                version.set_version(root, '0.1.6')
            self.assertEqual(json.loads((root / 'package.json').read_text())['version'], '0.1.5')


class PrepareGitIntegrationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.remote = self.root / 'origin.git'
        self.repo.mkdir()
        self.run_command('git', 'init', '--bare', str(self.remote), cwd=self.root)
        self.run_command('git', 'init', '-b', 'main')
        self.run_command('git', 'config', 'user.name', 'Test')
        self.run_command('git', 'config', 'user.email', 'test@example.invalid')
        self.run_command('git', 'config', 'commit.gpgsign', 'false')
        self.run_command('git', 'remote', 'add', 'origin', str(self.remote))
        (self.repo / 'src-tauri').mkdir()
        target = self.repo / '.github/scripts/auto-release'
        target.mkdir(parents=True)
        shutil.copy(SCRIPT, target / 'version.py')
        shutil.copy(SCRIPT.parent / 'prepare.sh', target / 'prepare.sh')
        shutil.copy(SCRIPT.parent / 'reserve.sh', target / 'reserve.sh')
        shutil.copy(SCRIPT.parent / 'publish.sh', target / 'publish.sh')
        shutil.copy(SCRIPT.parent / 'release-notes.md', target / 'release-notes.md')
        (self.repo / 'package.json').write_text('{"version":"0.1.5"}')
        (self.repo / 'package-lock.json').write_text('{"version":"0.1.5","packages":{"":{"version":"0.1.5"}}}')
        (self.repo / 'src-tauri/tauri.conf.json').write_text('{"version":"0.1.5"}')
        (self.repo / 'src-tauri/Cargo.toml').write_text('[package]\nname = "auto-clicker"\nversion = "0.1.5"\n')
        (self.repo / 'src-tauri/Cargo.lock').write_text('[[package]]\nname = "auto-clicker"\nversion = "0.1.5"\n')
        self.run_command('git', 'add', '.')
        self.run_command('git', 'commit', '-m', 'source')
        self.source = self.run_command('git', 'rev-parse', 'HEAD').strip()
        self.run_command('git', 'tag', 'v0.1.5')
        self.run_command('git', 'push', 'origin', 'main', '--tags')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        fake_gh = self.bin / 'gh'
        fake_gh.write_text('#!/bin/sh\nprintf "v0.1.5\\n"\n')
        fake_gh.chmod(0o755)

    def run_command(self, *args, cwd=None, env=None):
        return subprocess.run(args, cwd=cwd or self.repo, env=env, text=True,
                              check=True, capture_output=True).stdout

    def prepare(self, source):
        out = self.root / 'output'
        out.write_text('')
        env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}', SOURCE_SHA=source,
                   GITHUB_REPOSITORY='owner/repo', GITHUB_OUTPUT=str(out), RUNNER_TEMP=str(self.root))
        self.run_command('bash', '.github/scripts/auto-release/prepare.sh', env=env)
        return dict(line.split('=', 1) for line in out.read_text().splitlines())

    def test_version_commit_is_fast_forward_and_retry_reuses_it(self):
        first = self.prepare(self.source)
        self.assertEqual(first['release_tag'], 'v0.1.6')
        self.assertEqual(first['should_release'], 'true')
        self.assertEqual(self.run_command('git', 'rev-parse', 'origin/main').strip(), first['release_sha'])
        self.assertEqual(self.run_command('git', 'rev-parse', 'HEAD^').strip(), self.source)
        self.assertEqual(self.prepare(self.source), first)

    def test_stale_source_does_not_write_to_main(self):
        (self.repo / 'extra.txt').write_text('another developer')
        self.run_command('git', 'add', 'extra.txt')
        self.run_command('git', 'commit', '-m', 'new work')
        newer = self.run_command('git', 'rev-parse', 'HEAD').strip()
        self.run_command('git', 'push', 'origin', 'main')
        self.assertEqual(self.prepare(self.source), {'should_release': 'false'})
        self.assertEqual(self.run_command('git', 'rev-parse', 'origin/main').strip(), newer)

    def reserve(self, release_sha, tag, releases=''):
        out = self.root / 'reserve-output'
        out.write_text('')
        release_file = self.root / 'fake-releases'
        release_file.write_text(releases)
        trace = self.root / 'fake-gh-trace'
        trace.write_text('')
        fake_gh = self.bin / 'gh'
        fake_gh.write_text('#!/bin/sh\nif [ "$1" = api ]; then cat "$GH_FAKE_RELEASES"; else printf "%s\\n" "$*" >> "$GH_FAKE_TRACE"; fi\n')
        fake_gh.chmod(0o755)
        env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}', RELEASE_SHA=release_sha,
                   RELEASE_TAG=tag, GITHUB_REPOSITORY='owner/repo', GITHUB_OUTPUT=str(out),
                   GH_FAKE_RELEASES=str(release_file), GH_FAKE_TRACE=str(trace))
        result = subprocess.run(['bash', '.github/scripts/auto-release/reserve.sh'], cwd=self.repo,
                                env=env, text=True, capture_output=True)
        return result, out.read_text(), trace.read_text()

    def test_reserve_creates_owned_draft_and_retry_reuses_tag(self):
        info = self.prepare(self.source)
        result, out, trace = self.reserve(info['release_sha'], info['release_tag'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(out.strip(), 'should_build=true')
        self.assertIn('release create v0.1.6 --verify-tag --draft', trace)
        self.assertEqual(self.run_command('git', 'ls-remote', '--refs', 'origin', 'refs/tags/v0.1.6').split()[0], info['release_sha'])
        draft = json.dumps({'tag_name': 'v0.1.6', 'name': f'Auto Clicker v0.1.6 [auto {info["release_sha"]}]',
                            'draft': True, 'prerelease': False, 'id': 2})
        result, out, trace = self.reserve(info['release_sha'], info['release_tag'], draft)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(out.strip(), 'should_build=true')
        self.assertEqual(trace, '')

    def test_reserve_refuses_unowned_draft_before_pushing_tag(self):
        info = self.prepare(self.source)
        foreign = json.dumps({'tag_name': 'v0.1.6', 'name': 'Someone else',
                              'draft': True, 'prerelease': False, 'id': 3})
        result, _, trace = self.reserve(info['release_sha'], info['release_tag'], foreign)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not owned', result.stderr)
        self.assertEqual(trace, '')
        self.assertEqual(self.run_command('git', 'ls-remote', '--refs', 'origin', 'refs/tags/v0.1.6'), '')

    def publish(self, info, published='v0.1.4', fail_notes=False):
        trace = self.root / 'publish-trace'
        trace.write_text('')
        fake_gh = self.bin / 'gh'
        fake_gh.write_text('''#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
tag, sha = os.environ['RELEASE_TAG'], os.environ['RELEASE_SHA']
if a[:2] == ['release', 'view']:
    print(json.dumps({'databaseId': 123, 'isDraft': True, 'isPrerelease': False,
                      'name': f'Auto Clicker {tag} [auto {sha}]', 'tagName': tag}))
elif a[:2] == ['api', '--paginate']:
    print(os.environ['GH_FAKE_PUBLISHED'])
elif a[:3] == ['api', '--method', 'POST']:
    if os.environ.get('GH_FAKE_NOTES_FAIL') == 'true': raise SystemExit(1)
    data = json.load(open(a[a.index('--input') + 1]))
    assert data['tag_name'] == tag and data['target_commitish'] == sha
    print(json.dumps({'body': '## Changes\\n* User change'}))
elif a[:3] == ['api', '--method', 'PATCH']:
    with open(os.environ['GH_FAKE_TRACE'], 'a') as f: f.write('PATCH\\n')
    data = json.load(open(a[a.index('--input') + 1]))
    print(json.dumps({'draft': data['draft'], 'tag_name': tag, 'body': data['body']}))
elif a[0] == 'api' and '/releases/latest' in a[1]:
    print(tag)
else:
    raise SystemExit('unexpected gh arguments: ' + repr(a))
''')
        fake_gh.chmod(0o755)
        env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}', RELEASE_SHA=info['release_sha'],
                   RELEASE_TAG=info['release_tag'], GITHUB_REPOSITORY='owner/repo', RUNNER_TEMP=str(self.root),
                   GH_FAKE_PUBLISHED=published, GH_FAKE_TRACE=str(trace), GH_FAKE_NOTES_FAIL=str(fail_notes).lower())
        result = subprocess.run(['bash', '.github/scripts/auto-release/publish.sh'], cwd=self.repo,
                                env=env, text=True, capture_output=True)
        return result, trace.read_text()

    def test_publish_writes_required_notes_after_checks(self):
        info = self.prepare(self.source)
        self.assertEqual(self.reserve(info['release_sha'], info['release_tag'])[0].returncode, 0)
        result, trace = self.publish(info)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(trace, 'PATCH\n')
        body = json.loads((self.root / 'publish-release.json').read_text())
        self.assertFalse(body['draft'])
        self.assertEqual(body['make_latest'], 'legacy')
        self.assertIn('physical-keyboard emergency stop failure', body['body'])
        self.assertIn('Windows', body['body'])
        self.assertIn('User change', body['body'])
        notes_request = json.loads((self.root / 'generate-notes.json').read_text())
        self.assertEqual(notes_request['previous_tag_name'], 'v0.1.4')

    def test_publish_does_not_publish_when_generating_notes_fails(self):
        info = self.prepare(self.source)
        self.assertEqual(self.reserve(info['release_sha'], info['release_tag'])[0].returncode, 0)
        result, trace = self.publish(info, fail_notes=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(trace, '')

    def test_publish_refuses_newer_stable_release(self):
        info = self.prepare(self.source)
        self.assertEqual(self.reserve(info['release_sha'], info['release_tag'])[0].returncode, 0)
        result, trace = self.publish(info, published='v0.1.7')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('newer stable', result.stderr)
        self.assertEqual(trace, '')

    def test_publish_leaves_draft_when_main_has_advanced(self):
        info = self.prepare(self.source)
        self.assertEqual(self.reserve(info['release_sha'], info['release_tag'])[0].returncode, 0)
        (self.repo / 'extra.txt').write_text('newer main')
        self.run_command('git', 'add', 'extra.txt')
        self.run_command('git', 'commit', '-m', 'newer main')
        self.run_command('git', 'push', 'origin', 'HEAD:main')
        result, trace = self.publish(info)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('leaving this release as a draft', result.stdout)
        self.assertEqual(trace, '')


if __name__ == '__main__':
    unittest.main()
