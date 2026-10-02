#!/usr/bin/env python3
"""Assemble a clean app; a previous Preview must never leak into another channel."""
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys


def package(binary_dir, distribution):
    if distribution not in ('direct', 'preview', 'appstore'):
        raise ValueError('Unknown SUMI_DISTRIBUTION')
    preview = distribution == 'preview'
    name = 'Sumi Preview' if preview else 'Sumi'
    app = Path('build') / (name + '.app')
    if app.exists():
        shutil.rmtree(app)
    contents = app / 'Contents'
    resources = contents / 'Resources'
    shutil.copytree('Resources', resources, symlinks=True)
    (resources / 'Preview-Info.plist').unlink()
    for directory in ('MacOS', 'Helpers'):
        (contents / directory).mkdir(parents=True)
    shutil.copy2(binary_dir / 'Sumi', contents / 'MacOS/Sumi')
    shutil.copy2(binary_dir / 'SumiMCP', contents / 'Helpers/SumiMCP')
    shutil.copy2('.tools/tinymist', contents / 'Helpers/tinymist')
    # Native SwiftPM embeds its PackageFrameworks path ahead of the app's rpath.
    # Remove build-machine paths so cold-launch checks exercise bundled code.
    for executable in (contents / 'MacOS/Sumi', contents / 'Helpers/SumiMCP'):
        commands = subprocess.check_output(['otool', '-l', str(executable)], text=True)
        for path in re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset', commands):
            if path.startswith(str(Path('.build').resolve()) + '/'):
                subprocess.run(['install_name_tool', '-delete_rpath', path, str(executable)], check=True)
    for bundle in binary_dir.glob('*.bundle'):
        shutil.copytree(bundle, resources / bundle.name, symlinks=True)
    info = plistlib.loads(Path('Resources/Info.plist').read_bytes())
    info['SumiDistribution'] = distribution
    info['SumiCommit'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    if preview:
        info.update(plistlib.loads(Path('Resources/Preview-Info.plist').read_bytes()))
        build = os.environ.get('SUMI_BUILD_NUMBER', '1.0')
        if not re.fullmatch(r'[1-9][0-9]*\.[1-9][0-9]*|1\.0', build):
            raise ValueError('Preview build must be run_number.run_attempt')
        info['CFBundleVersion'] = build
        frameworks = list(Path('.build/artifacts/sparkle').glob('**/Sparkle.framework'))
        if len(frameworks) != 1:
            raise RuntimeError('Expected one resolved Sparkle framework')
        (contents / 'Frameworks').mkdir()
        shutil.copytree(frameworks[0], contents / 'Frameworks/Sparkle.framework', symlinks=True)
        for language, title in [('en', 'Sumi Preview'), ('zh-Hans', '留白预览版')]:
            (resources / (language + '.lproj') / 'InfoPlist.strings').write_text(
                f'"CFBundleName" = "{title}";\n"CFBundleDisplayName" = "{title}";\n')
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    print(app)


if __name__ == '__main__':
    package(Path(sys.argv[1]), os.environ.get('SUMI_DISTRIBUTION', 'direct'))
