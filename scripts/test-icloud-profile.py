#!/usr/bin/env python3
"""Exercise release-profile rejection using an isolated synthetic profile."""
import copy
import datetime
import hashlib
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('prepare_profile', Path(__file__).with_name('prepare-icloud-profile.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ProfileValidation(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime(2026, 10, 1)
        self.cert = b'test certificate, not a credential'
        self.identity = hashlib.sha1(self.cert).hexdigest()
        self.profile = {
            'TeamIdentifier': ['TESTTEAM'], 'ApplicationIdentifierPrefix': ['TESTPREFIX'],
            'ExpirationDate': datetime.datetime(2030, 1, 1), 'ProvisionsAllDevices': True,
            'DeveloperCertificates': [self.cert],
            'Entitlements': {
                'com.apple.application-identifier': 'TESTPREFIX.app.leftblank.writer',
                'com.apple.developer.team-identifier': 'TESTTEAM',
                'com.apple.developer.icloud-container-identifiers': ['iCloud.app.leftblank.writer'],
                'com.apple.developer.ubiquity-container-identifiers': ['iCloud.app.leftblank.writer'],
                'com.apple.developer.icloud-services': '*',
                'com.apple.developer.icloud-container-environment': 'Production',
                'com.apple.developer.ubiquity-kvstore-identifier': 'TESTPREFIX.*',
            },
        }

    def validate(self, profile):
        return module.entitlements(profile, 'TESTTEAM', self.identity, self.now)

    def test_valid_profile_scopes_wildcards_to_leftblank(self):
        result = self.validate(self.profile)
        self.assertEqual(result['com.apple.developer.ubiquity-kvstore-identifier'], 'TESTPREFIX.app.leftblank.writer')
        self.assertEqual(result['com.apple.developer.icloud-services'], ['CloudDocuments'])
        self.assertNotIn('keychain-access-groups', result)

    def test_rejects_invalid_distribution_identity_and_expiry(self):
        for key, value in [('TeamIdentifier', ['OTHER']), ('ExpirationDate', self.now), ('ProvisionsAllDevices', False), ('ProvisionedDevices', ['test']), ('DeveloperCertificates', [b'other']), ('ApplicationIdentifierPrefix', [])]:
            with self.subTest(key=key):
                profile = copy.deepcopy(self.profile)
                profile[key] = value
                with self.assertRaises(ValueError): self.validate(profile)

    def test_rejects_missing_capabilities_and_debugging(self):
        for key in self.profile['Entitlements']:
            with self.subTest(key=key):
                profile = copy.deepcopy(self.profile)
                del profile['Entitlements'][key]
                with self.assertRaises(ValueError): self.validate(profile)
        profile = copy.deepcopy(self.profile)
        profile['Entitlements']['com.apple.security.get-task-allow'] = True
        with self.assertRaises(ValueError): self.validate(profile)

if __name__ == '__main__': unittest.main()
