#!/usr/bin/env python3
"""Publish versioned binaries first, then advance the stable signed feed."""
import json
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

REPO = 'leftblank-app/leftblank'
FEED_TAG = 'preview-latest'


def gh(*args, **kwargs):
    return subprocess.check_output(['gh', *args, '--repo', REPO], text=True, **kwargs).strip()


def release_exists(tag):
    result = subprocess.run(['gh', 'release', 'view', tag, '--repo', REPO, '--json', 'tagName'],
                            text=True, capture_output=True)
    if result.returncode == 0:
        return True
    if 'release not found' in result.stderr.lower():
        return False
    raise RuntimeError(result.stderr.strip())


def main():
    directory = Path('build/release')
    feed = ET.parse(directory / 'appcast.xml')
    build = feed.findtext('.//{http://www.andymatuschak.org/xml-namespaces/sparkle}version')
    tag = 'preview-' + build
    commit = os.environ['GITHUB_SHA']
    # GITHUB_SHA must be the commit that passed the dependency job, never a fresh checkout of main.
    subprocess.run(['git', 'merge-base', '--is-ancestor', commit, 'origin/main'], check=True)
    notes = directory / 'notes.md'
    notes.write_text(f'Tested main build **{build}**, commit `{commit}`.\n\nDownload the ZIP, unzip and drag **LeftBlank Preview.app** to Applications. Preview uses its own local library and offers signed updates. It does not access the stable app\'s iCloud library.\n')
    if not release_exists(tag):
        gh('release', 'create', tag, *map(str, directory.glob('*.zip')), *map(str, directory.glob('*.sha256')),
           str(directory / 'appcast.xml'), '--target', commit, '--prerelease', '--latest=false',
           '--title', f'LeftBlank Preview {build}', '--notes-file', str(notes))
    if not release_exists(FEED_TAG):
        gh('release', 'create', FEED_TAG, '--target', commit, '--prerelease', '--latest=false',
           '--title', 'LeftBlank Preview updates', '--notes', 'Signed update feed for LeftBlank Preview. The feed tag stays fixed; each app archive has its own immutable build tag.')
    # GitHub concurrency prevents simultaneous writes. Also reject an old rerun
    # so it can never make a previously published newer build disappear.
    current = directory / 'current-feed'
    current.mkdir(exist_ok=True)
    assets = json.loads(gh('release', 'view', FEED_TAG, '--json', 'assets'))['assets']
    if any(asset['name'] == 'appcast.xml' for asset in assets):
        gh('release', 'download', FEED_TAG, '--pattern', 'appcast.xml', '--dir', str(current), '--clobber')
        previous = ET.parse(current / 'appcast.xml').findtext('.//{http://www.andymatuschak.org/xml-namespaces/sparkle}version')
        if tuple(map(int, previous.split('.'))) >= tuple(map(int, build.split('.'))):
            print(f'Feed already points to {previous}; preserving it.')
            return
    gh('release', 'upload', FEED_TAG, str(directory / 'appcast.xml'), '--clobber')
    print(f'Published LeftBlank Preview {build}.')


if __name__ == '__main__':
    main()
