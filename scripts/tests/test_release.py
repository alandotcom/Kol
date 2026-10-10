"""Exercise release gates without uploading, publishing, or installing software."""

import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STUB = r'''#!/usr/bin/env python3
import hashlib, json, os, plistlib, sys
from pathlib import Path

command = Path(sys.argv[0]).name
args = sys.argv[1:]
scenario = os.environ.get('SCENARIO', '')
with open(os.environ['CALL_LOG'], 'a') as log:
    log.write(json.dumps([command, *args]) + '\n')

if command == 'git':
    if args == ['branch', '--show-current']:
        print('main')
    elif args[:2] == ['rev-parse', '--verify']:
        sys.exit(1)
elif command == 'sysctl':
    print(2)
elif command == 'xcodebuildmcp':
    print('24 tests passed, 0 failed')
elif command == 'xcodebuild':
    if scenario == 'build-failure':
        sys.exit(1)
    derived = Path(args[args.index('-derivedDataPath') + 1])
    config = args[args.index('-configuration') + 1]
    app = derived / 'Build/Products' / config / 'Kol.app/Contents'
    app.mkdir(parents=True, exist_ok=True)
    (app / 'Info.plist').write_bytes(Path('Kol/Info.plist').read_bytes())
elif command == 'xcrun':
    if args[:2] == ['notarytool', 'history']:
        if scenario == 'credentials':
            sys.exit(69)
        print('{}')
    elif args[:2] == ['notarytool', 'submit']:
        if scenario == 'malformed':
            print('not JSON')
        else:
            status = 'Accepted'
            if scenario in ('rejected', 'rejected-exit'):
                status = 'Invalid'
            elif scenario == 'timeout':
                status = 'In Progress'
            print(json.dumps({'id': 'fixture-submission', 'status': status}))
        sys.exit(75 if scenario == 'timeout' else 65 if scenario == 'rejected-exit' else 0)
    elif args[:2] == ['notarytool', 'log']:
        Path(args[-1]).write_text('{}')
    elif args[:2] == ['stapler', 'staple']:
        if scenario == 'staple':
            sys.exit(1)
        (Path(args[-1]) / 'Contents/ticket').write_text('fixture-ticket')
    elif args[:2] == ['stapler', 'validate']:
        if scenario == 'ticket':
            sys.exit(1)
        if scenario == 'archive-ticket' and 'extracted' in args[-1]:
            sys.exit(1)
        if not (Path(args[-1]) / 'Contents/ticket').exists():
            sys.exit(1)
elif command == 'codesign' and '--verify' in args:
    if scenario == 'signature' or (scenario == 'archive-signature' and 'extracted' in args[-1]):
        sys.exit(1)
elif command == 'spctl' and scenario == 'gatekeeper':
    sys.exit(1)
elif command == 'gh' and args[:2] == ['release', 'view']:
    archive = next(Path('build').glob('Kol-v*.zip'))
    print(json.dumps({'assets': [{
        'name': archive.name, 'state': 'uploaded', 'size': archive.stat().st_size,
        'digest': 'sha256:' + hashlib.sha256(archive.read_bytes()).hexdigest()
    }]}))
'''


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='kol-release-test-')
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        (self.repo / 'scripts').mkdir()
        for name in ('release.sh', 'build-install.sh', 'prepare-release.py'):
            shutil.copy2(ROOT / 'scripts' / name, self.repo / 'scripts' / name)
        (self.repo / 'Kol/Resources').mkdir(parents=True)
        (self.repo / 'Kol.xcodeproj').mkdir()
        (self.repo / '.changeset').mkdir()
        (self.repo / '.changeset/fixture.md').write_text('---\n"kol-app": patch\n---\nImprove installation.\n')
        (self.repo / 'package.json').write_text('{"version":"2.0.0"}')
        (self.repo / 'CHANGELOG.md').write_text('# Changelog\n\n## 2.0.0\n')
        (self.repo / 'Kol.xcodeproj/project.pbxproj').write_text(
            'CURRENT_PROJECT_VERSION = 1;\nMARKETING_VERSION = 2.0.0;\nDEVELOPMENT_TEAM = ABCDE12345;\n'
        )
        (self.repo / 'Kol/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.alandotcom.Kol',
            'CFBundleShortVersionString': '2.0.0', 'CFBundleVersion': '1',
        }))
        self.bin = self.repo / 'bin'
        self.bin.mkdir()
        for command in ('git', 'gh', 'xcrun', 'xcodebuildmcp', 'xcodebuild',
                        'codesign', 'spctl', 'pkill', 'rsync', 'sysctl'):
            path = self.bin / command
            path.write_text(STUB)
            path.chmod(0o755)
        self.log = self.repo / 'calls.jsonl'
        self.env = {**os.environ, 'PATH': f'{self.bin}:/usr/bin:/bin',
                    'CALL_LOG': str(self.log), 'KOL_DERIVED_DATA_PATH': str(self.repo / 'build/DerivedData'),
                    'KOL_NOTARY_PROFILE': 'fixture-profile',
                    'KOL_SIGNING_IDENTITY': 'Developer ID Application: Example Identity',
                    'KOL_SIGNING_TEAM': 'ABCDE12345',
                    'KOL_NOTARY_TIMEOUT': '2m'}

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def run_script(self, name='release.sh', args=('2.0.1',), scenario=''):
        return subprocess.run(['bash', str(self.repo / 'scripts' / name), *args],
                              cwd=self.repo, env={**self.env, 'SCENARIO': scenario},
                              text=True, capture_output=True)

    def assert_unpublished(self):
        for call in self.calls():
            self.assertNotIn(call[:2], (['git', 'commit'], ['git', 'tag'], ['git', 'push']))
            self.assertNotEqual(call[:2], ['gh', 'release'])

    def test_accepted_release_packages_ticket_before_publishing(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        calls = self.calls()
        submit = next(c for c in calls if c[:3] == ['xcrun', 'notarytool', 'submit'])
        self.assertIn('fixture-profile', submit)
        self.assertIn('2m', submit)
        self.assertIn('--wait', submit)
        verification = self.repo / 'build/verification/release-2.0.1'
        self.assertEqual((verification / 'extracted/Kol.app/Contents/ticket').read_text(), 'fixture-ticket')
        final_check = next(i for i, c in enumerate(calls)
                           if c[:3] == ['codesign', '--verify', '--deep'] and 'extracted' in c[-1])
        commit = next(i for i, c in enumerate(calls) if c[:2] == ['git', 'commit'])
        self.assertLess(final_check, commit)
        self.assertTrue(any(c[:3] == ['gh', 'release', 'edit'] and '--draft=false' in c for c in calls))
        self.assertIn('notarized by Apple', (verification / 'notes.md').read_text())
        self.assertFalse(any(c[0] in ('rsync', 'pkill') or '--force' in c for c in calls))

    def test_failed_credentials_do_not_change_metadata(self):
        result = self.run_script(scenario='credentials')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('store-credentials', result.stderr)
        self.assertEqual(json.loads((self.repo / 'package.json').read_text())['version'], '2.0.0')
        self.assertTrue((self.repo / '.changeset/fixture.md').exists())
        self.assert_unpublished()

    def test_notarization_and_verification_failures_block_publication(self):
        for scenario in ('rejected', 'rejected-exit', 'timeout', 'malformed',
                         'staple', 'ticket', 'gatekeeper', 'archive-ticket',
                         'signature', 'archive-signature', 'build-failure'):
            with self.subTest(scenario=scenario):
                # Use a fresh fixture for each destructive release preparation.
                case = ReleaseTests()
                case.setUp()
                try:
                    result = case.run_script(scenario=scenario)
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    case.assert_unpublished()
                    if scenario in ('rejected', 'rejected-exit', 'timeout'):
                        self.assertTrue(any(c[:3] == ['xcrun', 'notarytool', 'log'] for c in case.calls()))
                finally:
                    case.doCleanups()

    def test_distribution_build_uses_xcode_signing_without_installing(self):
        result = self.run_script('build-install.sh', ('--release',))
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        build = next(c for c in calls if c[0] == 'xcodebuild')
        for setting in ('CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_STYLE=Manual',
                        'ENABLE_HARDENED_RUNTIME=YES', 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO',
                        'OTHER_CODE_SIGN_FLAGS=--timestamp',
                        'DEVELOPMENT_TEAM=ABCDE12345',
                        'CODE_SIGN_IDENTITY=Developer ID Application: Example Identity'):
            self.assertIn(setting, build)
        self.assertFalse(any(c[0] in ('rsync', 'pkill') or '--force' in c for c in calls))

    def test_debug_build_keeps_local_signing_and_installation(self):
        result = self.run_script('build-install.sh', ('--debug',))
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertIn('CODE_SIGNING_ALLOWED=NO', next(c for c in calls if c[0] == 'xcodebuild'))
        self.assertTrue(any(c[0] == 'codesign' and '--force' in c for c in calls))
        self.assertTrue(any(c[0] == 'rsync' and c[-1] == '/Applications/Kol Debug.app/' for c in calls))

    def test_distribution_build_defaults_to_project_team(self):
        del self.env['KOL_SIGNING_TEAM']
        result = self.run_script('build-install.sh', ('--release',))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('DEVELOPMENT_TEAM=ABCDE12345', next(c for c in self.calls() if c[0] == 'xcodebuild'))


if __name__ == '__main__':
    unittest.main()
