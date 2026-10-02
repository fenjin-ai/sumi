#!/usr/bin/env python3
"""Exercise real Sparkle signing, public-key verification and tamper rejection."""
import base64
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent.parent


class PreviewReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(['scripts/sparkle-tools.sh'], cwd=ROOT, check=True)

    def test_signed_archive_feed_and_wrong_key(self):
        key = base64.b64encode(os.urandom(32))
        public = subprocess.check_output(['swift', '-module-cache-path', str(ROOT / '.build/update-module-cache'),
                                          str(ROOT / 'scripts/verify-update.swift'), '--public-key'], input=key).decode().strip()
        with tempfile.TemporaryDirectory(prefix='sumi-update-contract-', dir=os.environ['TMPDIR']) as temporary:
            root = Path(temporary)
            (root / 'scripts').symlink_to(ROOT / 'scripts', target_is_directory=True)
            (root / '.tools').symlink_to(ROOT / '.tools', target_is_directory=True)
            (root / 'Resources').mkdir()
            info = plistlib.loads((ROOT / 'Resources/Preview-Info.plist').read_bytes())
            info['SUPublicEDKey'] = public
            (root / 'Resources/Preview-Info.plist').write_bytes(plistlib.dumps(info))
            info.update(CFBundleVersion='91.1', CFBundleShortVersionString='0.5.0', SumiCommit='abcdef123456')
            archive = root / 'Sumi-Preview-test.zip'
            with zipfile.ZipFile(archive, 'w') as bundle:
                bundle.writestr('Sumi Preview.app/Contents/Info.plist', plistlib.dumps(info))
            environment = {**os.environ, 'SPARKLE_PRIVATE_KEY': key.decode()}
            def generate(build='91.1', **extra):
                return subprocess.run(['python3', str(ROOT / 'scripts/preview-feed.py'), str(archive), build],
                                      cwd=root, env={**environment, **extra}, capture_output=True)
            result = generate()
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            feed = root / 'appcast.xml'
            enclosure = ET.parse(feed).find('.//enclosure')
            self.assertIn('/preview-91.1/', enclosure.attrib['url'])
            signature = enclosure.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature']
            # The public key compiled into the application independently accepts the archive.
            verifier = ['swift', '-module-cache-path', str(ROOT / '.build/update-module-cache'),
                        str(ROOT / 'scripts/verify-update.swift'), public, signature, str(archive)]
            self.assertEqual(subprocess.run(verifier, capture_output=True).returncode, 0)
            self.assertNotEqual(generate('92.1').returncode, 0)
            self.assertNotEqual(generate(SPARKLE_PRIVATE_KEY=base64.b64encode(os.urandom(32)).decode()).returncode, 0)
            archive.write_bytes(archive.read_bytes() + b'corrupt')
            self.assertNotEqual(subprocess.run(verifier, capture_output=True).returncode, 0)
            feed.write_bytes(feed.read_bytes().replace(b'Tested main', b'Changed main'))
            result = subprocess.run([str(ROOT / '.tools/sparkle/bin/sign_update'), '--ed-key-file', '-',
                                     '--verify', str(feed)], input=key, capture_output=True)
            self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
