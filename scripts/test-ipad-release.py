#!/usr/bin/env python3
"""Offline iPad signing, archive and platform isolation release contracts."""
import copy
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest

import appstore_connect as asc
import ipad_release as ipad

spec = importlib.util.spec_from_file_location('mac_release_tests', Path(__file__).with_name('test-appstore-release.py'))
mac = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mac)


class MetadataTests(unittest.TestCase):
    def test_bilingual_metadata_and_confirmed_subscription(self):
        result = ipad.metadata(ipad.ROOT)
        self.assertEqual(result['platform'], 'IOS')
        self.assertEqual(result['storefront']['subscription']['product_id'], ipad.PRODUCT)
        self.assertEqual(set(result['localizations']), {'en-US', 'zh-Hans'})

    def test_price_or_trial_drift_stops_release(self):
        with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as directory:
            root = Path(directory)
            (root / 'iPad/Storefront').mkdir(parents=True)
            (root / 'iPad/Info.plist').write_bytes((ipad.ROOT / 'iPad/Info.plist').read_bytes())
            original = json.loads((ipad.ROOT / 'iPad/Storefront/manifest.json').read_text())
            for field, value in [('base_price', '3.99'), ('period', 'ONE_YEAR'),
                                  ('introductory_offer', {'mode': 'FREE_TRIAL', 'duration': 'ONE_MONTH'})]:
                with self.subTest(field=field):
                    store = copy.deepcopy(original)
                    store['subscription'][field] = value
                    (root / 'iPad/Storefront/manifest.json').write_text(json.dumps(store))
                    with self.assertRaisesRegex(ValueError, 'business model'):
                        ipad.metadata(root)


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.identity = hashlib.sha1(b'certificate').hexdigest().upper()
        self.profile = {
            'Platform': ['iOS'], 'UUID': 'uuid', 'TeamIdentifier': ['TEAM'],
            'DeveloperCertificates': [b'certificate'],
            'ExpirationDate': datetime.datetime(2030, 1, 1),
            'Entitlements': {
                'application-identifier': 'TEAM.' + ipad.BUNDLE, 'get-task-allow': False,
                'com.apple.developer.icloud-container-identifiers': ['iCloud.' + ipad.BUNDLE],
                'com.apple.developer.ubiquity-container-identifiers': ['iCloud.' + ipad.BUNDLE],
                'com.apple.developer.icloud-services': ['CloudDocuments'],
                'com.apple.developer.icloud-container-environment': 'Production',
                'com.apple.developer.ubiquity-kvstore-identifier': 'TEAM.' + ipad.BUNDLE,
            },
        }

    def test_appstore_production_profile(self):
        self.assertEqual(ipad.validate_profile(self.profile, self.identity), ('TEAM', 'uuid'))

    def test_development_adhoc_enterprise_mac_and_expired_profiles_stop(self):
        for changes in [{'Platform': ['OSX']}, {'ProvisionedDevices': ['device']},
                        {'ProvisionsAllDevices': True}, {'ExpirationDate': datetime.datetime(2020, 1, 1)}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                ipad.validate_profile({**self.profile, **changes}, self.identity)
        for key, value in [('application-identifier', 'TEAM.other'), ('get-task-allow', True),
                           ('com.apple.developer.icloud-container-environment', 'Development'),
                           ('com.apple.developer.ubiquity-container-identifiers', []),
                           ('com.apple.developer.ubiquity-kvstore-identifier', 'OTHER.*')]:
            with self.subTest(key=key):
                profile = copy.deepcopy(self.profile)
                profile['Entitlements'][key] = value
                with self.assertRaises(ValueError):
                    ipad.validate_profile(profile, self.identity)
        with self.assertRaisesRegex(ValueError, 'certificate'):
            ipad.validate_profile(self.profile, 'NOT_THE_CERTIFICATE')


class ArchiveTests(unittest.TestCase):
    def test_versions_device_family_crypto_and_desktop_components(self):
        with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as directory:
            archive = Path(directory)
            app = archive / 'Products/Applications/LeftBlank.app'
            app.mkdir(parents=True)
            (app / 'LeftBlank').write_bytes(b'executable')
            core = app / 'Frameworks/LeftBlankCore.framework/LeftBlankCore'
            core.parent.mkdir(parents=True)
            core.write_bytes(b'framework')
            info = {'CFBundleIdentifier': ipad.BUNDLE, 'CFBundleShortVersionString': '1.0.0',
                    'CFBundleVersion': '1', 'UIDeviceFamily': [2], 'CFBundleExecutable': 'LeftBlank',
                    'ITSAppUsesNonExemptEncryption': False, 'CFBundleSupportedPlatforms': ['iPhoneOS']}
            path = app / 'Info.plist'
            path.write_bytes(plistlib.dumps(info))
            expected = {'version': '1.0.0', 'build': '1'}
            (app / 'Sparkle-LICENSE.txt').write_text('Shared third-party attribution')
            (app / 'sparkle.svg').write_text('<svg/>')
            self.assertEqual(ipad.validate_archive(archive, expected), app)
            for key, value in [('CFBundleVersion', '2'), ('UIDeviceFamily', [1, 2]),
                               ('ITSAppUsesNonExemptEncryption', True), ('CFBundleSupportedPlatforms', ['MacOSX'])]:
                with self.subTest(key=key):
                    path.write_bytes(plistlib.dumps({**info, key: value}))
                    with self.assertRaisesRegex(ValueError, key):
                        ipad.validate_archive(archive, expected)
            path.write_bytes(plistlib.dumps(info))
            for name in ['LeftBlankMCP', 'Sparkle.framework', 'LeftBlankAutomation.framework']:
                unexpected = app / name
                if name.endswith('.framework'):
                    unexpected.mkdir()
                else:
                    unexpected.touch()
                with self.assertRaisesRegex(ValueError, 'desktop-only'):
                    ipad.validate_archive(archive, expected)
                if unexpected.is_dir():
                    unexpected.rmdir()
                else:
                    unexpected.unlink()
            for name in ['LeftBlank.storekit', 'LeftBlankTests.xctest']:
                unexpected = app / name
                unexpected.touch()
                with self.assertRaisesRegex(ValueError, 'test-only'):
                    ipad.validate_archive(archive, expected)
                unexpected.unlink()
            core.unlink()
            with self.assertRaisesRegex(ValueError, 'shared Core framework'):
                ipad.validate_archive(archive, expected)


class PlatformTests(unittest.TestCase):
    def test_latest_required_ci_gate_must_pass(self):
        check = {'id': 1, 'name': 'build and test', 'conclusion': 'success', 'app': {'slug': 'github-actions'}}
        ipad.validate_ci([check])
        for records in [[], [{**check, 'conclusion': 'failure'}], [{**check, 'app': {'slug': 'other'}}],
                        [check, {**check, 'id': 2, 'conclusion': None}]]:
            with self.subTest(records=records), self.assertRaisesRegex(ValueError, 'gate has not passed'):
                ipad.validate_ci(records)

    def test_ios_filters_do_not_confuse_mac_builds_or_pending_versions(self):
        apple = mac.FakeApple()
        original = apple.list
        calls = []

        def list_platform(path, **query):
            calls.append((path, query))
            return original(path, **query)

        apple.list = list_platform
        release = asc.Release(apple, 'app', {'version': '1.0.0', 'build': '1'}, platform='IOS')
        self.assertTrue(release.preflight())
        self.assertTrue(any(query.get('filter[platform]') == 'IOS' for _, query in calls))
        self.assertTrue(any(query.get('filter[preReleaseVersion.platform]') == 'IOS' for _, query in calls))
        self.assertFalse(any('MAC_OS' in query.values() for _, query in calls))

    def test_initial_subscription_cannot_be_submitted_as_an_app_only_review(self):
        apple = mac.FakeApple()
        release = asc.Release(apple, 'app', {'version': '1.0.0', 'build': '1'}, platform='IOS')
        with self.assertRaisesRegex(RuntimeError, 'subscription group together'):
            release.submit(apple.build)
        self.assertEqual(apple.writes, [])


if __name__ == '__main__':
    unittest.main()
