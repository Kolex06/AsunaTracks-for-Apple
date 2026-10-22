#!/usr/bin/env python3
"""Validate every platform/extension version before a release can be published."""
import hashlib
import json
import pathlib
import plistlib
import sys
import zipfile

folder = pathlib.Path(sys.argv[1])
expected_build = sys.argv[2]
expected_version = sys.argv[3]
archives = {
    'AsunaTracks-macOS.zip': ('MacOSX', 2),
    'AsunaTracks-iPhone-iPad-unsigned.ipa': ('iPhoneOS', 4),
    'AsunaTracks-Apple-Watch-unsigned.zip': ('WatchOS', 2),
}
manifest = {'version': expected_version, 'build': expected_build, 'artifacts': []}
for filename, (platform, count) in archives.items():
    artifact = folder / filename
    bundles = []
    with zipfile.ZipFile(artifact) as archive:
        assert archive.testzip() is None, filename + ': corrupt archive'
        assert not any(p.endswith(('.mobileprovision', '.provisionprofile')) for p in archive.namelist()), filename + ': private provisioning profile'
        for name in archive.namelist():
            if name.startswith('__MACOSX/') or not name.endswith(('.app/Info.plist', '.appex/Info.plist', '.app/Contents/Info.plist', '.appex/Contents/Info.plist')):
                continue
            info = plistlib.loads(archive.read(name))
            assert info['CFBundleVersion'] == expected_build, (filename, name, 'wrong build')
            assert info['CFBundleShortVersionString'] == expected_version, (filename, name, 'wrong version')
            bundles.append({'path': name, 'identifier': info['CFBundleIdentifier'], 'build': info['CFBundleVersion'], 'platforms': info.get('CFBundleSupportedPlatforms'), 'device_families': info.get('UIDeviceFamily')})
        assert len(bundles) == count, (filename, 'missing app/widget bundle', len(bundles))
        assert platform in (next(b for b in bundles if b['path'].count('/') == min(x['path'].count('/') for x in bundles))['platforms'] or []), (filename, 'wrong platform')
        if platform == 'iPhoneOS':
            app = plistlib.loads(archive.read('Payload/AsunaTracks.app/Info.plist'))
            assert set(app['UIDeviceFamily']) == {1, 2}, 'IPA must support both iPhone and iPad'
    manifest['artifacts'].append({'name': filename, 'sha256': hashlib.sha256(artifact.read_bytes()).hexdigest(), 'bundles': bundles})
    print('Verified', filename, len(bundles), 'bundles, build', expected_build)
(folder / 'BUILD_MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
