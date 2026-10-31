#!/usr/bin/env python3
"""Verify the DMG, mounted app, installed copy, signature and offline resources."""
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess
import tempfile

base = pathlib.Path(__file__).resolve().parents[1]
archive = base / 'artifacts/TinyEditor-macOS-arm64.dmg'


def run(args):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert result.returncode == 0, result.stdout
    return result.stdout.strip()


image_check = run(['hdiutil', 'verify', str(archive)])
with tempfile.TemporaryDirectory(prefix='TinyEditor-dmg-check-', dir='/tmp') as directory:
    target = pathlib.Path(directory)
    mount = target / 'volume'
    mount.mkdir()
    run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(archive)])
    try:
        app = mount / 'TinyEditor.app'
        assert (mount / 'Applications').is_symlink()
        assert (mount / 'Applications').readlink() == pathlib.Path('/Applications')
        assert (mount / '安装说明.txt').is_file()
        assert not any('InputCheck' in p.name or 'cg-input' in p.name for p in app.rglob('*'))
        sign = run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)])
        identity = run(['codesign', '--display', '--verbose=4', str(app)])
        assert 'Signature=adhoc' in identity
        exe = app / 'Contents/MacOS/TinyEditor'
        arch = run(['lipo', '-archs', str(exe)])
        build = run(['xcrun', 'vtool', '-show-build', str(exe)])
        assert arch == 'arm64'
        assert re.search(r'minos\s+13\.0', build)
        preview = app / 'Contents/Resources/Preview'
        html = (preview / 'index.html').read_text()
        for path in re.findall(r'(?:src|href)="([^"]+)"', html):
            assert (preview / path).is_file(), path
        for path in re.findall(r'url\(([^)]+)\)', (preview / 'katex.min.css').read_text()):
            if not path.startswith('data:'):
                assert (preview / path.strip('\'"')).is_file(), path
        assert (app / 'Contents/Resources/TinyEditor.icns').is_file()
        assert (app / 'Contents/Resources/THIRD_PARTY_NOTICES.md').stat().st_size > 10000
        files = {str(p.relative_to(app)): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in sorted(app.rglob('*')) if p.is_file()}
        metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        installed = target / 'installed/TinyEditor.app'
        run(['ditto', str(app), str(installed)])
        installed_check = run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(installed)])
        assert hashlib.sha256((installed / 'Contents/MacOS/TinyEditor').read_bytes()).hexdigest() == files['Contents/MacOS/TinyEditor']
        result = {
            'version': metadata['CFBundleShortVersionString'], 'build': metadata['CFBundleVersion'],
            'architecture': arch, 'minimumSystemVerified': '13.0', 'signature': 'ad hoc', 'notarized': False,
            'format': 'DMG / UDZO', 'dmgIntegrity': True,
            'dmgSHA256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'dmgBytes': archive.stat().st_size,
            'appFileBytes': sum(p.stat().st_size for p in app.rglob('*') if p.is_file()),
            'resourceLinksComplete': True, 'codeSignatureVerification': sign,
            'codeSignatureIdentity': identity, 'buildVersion': build, 'files': files,
            'inputDriverExcluded': True, 'applicationsShortcut': True,
            'mountedReadOnly': True, 'installedCopyStrictSignature': installed_check,
            'dmgVerification': image_check,
        }
    finally:
        run(['hdiutil', 'detach', str(mount)])

(base / 'docs/distribution-results.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
(base / 'artifacts/SHA256SUMS.txt').write_text(result['dmgSHA256'] + '  ' + archive.name + '\n')
print(json.dumps({k: v for k, v in result.items()
                  if k not in ['files', 'codeSignatureIdentity', 'buildVersion']}, ensure_ascii=False, indent=2))
