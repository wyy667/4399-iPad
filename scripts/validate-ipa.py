"""Reject malformed iOS package layouts before releasing an IPA."""
import sys
import zipfile
import plistlib
import struct

with zipfile.ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None, 'Corrupt ZIP entry'
    names = archive.namelist()
    roots = {p.split('/')[1] for p in names if p.startswith('Payload/') and len(p.split('/')) > 2}
    assert len(roots) == 1, 'Expected one app in Payload'
    root = 'Payload/' + roots.pop() + '/'
    assert root.endswith('.app/'), 'Payload must contain an app bundle'
    assert not any(p.lower().startswith((root + 'Resources/').lower()) for p in names), 'Invalid iOS layout: root Resources directory'
    info = plistlib.loads(archive.read(root + 'Info.plist'))
    executable = archive.read(root + info['CFBundleExecutable'])
    magic, cpu = struct.unpack_from('<II', executable)
    assert magic == 0xfeedfacf and cpu == 0x100000c, 'Expected arm64 device executable'
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
    assert info['UIDeviceFamily'] == [1, 2]
    assert root + '_CodeSignature/CodeResources' in names, 'Missing code resource seal'
    assert root + 'WebAssets/bootstrap.js' in names
    assert root + 'WebAssets/Ruffle/ruffle.js' in names
    assert len([p for p in names if p.startswith(root + 'WebAssets/Ruffle/') and p.endswith('.wasm')]) == 2
    print('Validated IPA layout:', info['CFBundleIdentifier'], info['CFBundleShortVersionString'])
