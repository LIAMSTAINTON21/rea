"""Offline acceptance checks using PowerShell and a simulated adb.

Run: python3 examples/whoop/test_collector.py /absolute/path/to/pwsh
These exercise script behaviour, not real Android/provider compatibility.
"""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile


FAKE_ADB = r'''#!/usr/bin/env python3
import os, sys, zipfile
from pathlib import Path
a = sys.argv[1:]
mode = os.environ.get('WHOOP_TEST_SCENARIO', 'app')
if a == ['version']:
    print('Android Debug Bridge version 1.0.41 (simulated)')
elif a == ['devices', '-l']:
    print('List of devices attached')
    if mode != 'no-device':
        state = 'unauthorized' if mode == 'unauthorized' else 'device'
        print('TESTPIXEL\t' + state)
    if mode == 'multiple': print('OTHER\tdevice')
else:
    assert a[:2] == ['-s', 'TESTPIXEL'], a
    a = a[2:]
    if a[:2] == ['shell', 'getprop']:
        print({'ro.product.model': 'Pixel Test', 'ro.build.version.release': '17',
               'ro.build.version.sdk': '37'}[a[2]])
    elif a == ['shell', 'pm', 'list', 'packages']:
        print('package:com.example.whoop')
        if mode == 'ambiguous-package': print('package:com.example.whoop2')
    elif a[:3] == ['shell', 'dumpsys', 'package']:
        print('versionName=5.473.0\nversionCode=123\nPRIVATE FULL DUMP')
    elif a[:3] == ['shell', 'pm', 'path']:
        if mode != 'no-apks':
            print('package:/data/app/test/base.apk\npackage:/data/app/test/split.apk')
    elif a[0] == 'pull':
        if mode == 'pull-failure':
            print('simulated copy failure', file=sys.stderr)
            sys.exit(2)
        Path(a[2]).write_bytes(b'APK fixture: ' + a[1].encode())
    elif a[0] == 'bugreport':
        with zipfile.ZipFile(a[1], 'w') as z:
            z.writestr('bugreport.txt', 'PRIVATE FULL REPORT')
            if mode not in ['no-log', 'invalid-log']:
                z.writestr('FS/data/misc/bluetooth/logs/btsnoop_hci.log', b'btsnoop\x00' + b'fixture')
                z.writestr('../../escape/btsnoop_hci.log', b'btsnoop\x00' + b'fixture2')
            if mode == 'invalid-log':
                z.writestr('FS/data/misc/bluetooth/logs/btsnoop_hci.log', b'not a capture')
    else:
        raise AssertionError(a)
'''


def main():
    pwsh = sys.argv[1]
    collector = Path(__file__).with_name('Collect-Whoop.ps1').resolve()
    scenarios = ['app', 'capture', 'no-log', 'invalid-log', 'no-device',
                 'unauthorized', 'multiple', 'ambiguous-package', 'no-apks',
                 'pull-failure', 'existing-output']
    with tempfile.TemporaryDirectory(prefix='whoop-collector-test-') as temp:
        root = Path(temp)
        if os.name == 'nt':
            fake_python = root / 'fake-adb.py'
            fake_python.write_text(FAKE_ADB)
            fake = root / 'fake-adb.cmd'
            fake.write_text('@echo off\n"' + sys.executable + '" "' + str(fake_python) + '" %*\n')
        else:
            fake = root / 'fake-adb'
            fake.write_text(FAKE_ADB)
            fake.chmod(0o700)
        environment = dict(os.environ)
        if os.name == 'nt':
            # Let Windows PowerShell discover its own modules when launched
            # from PowerShell 7, whose inherited module path differs.
            for key in list(environment):
                if key.lower() == 'psmodulepath':
                    del environment[key]
        policy_args = ['-ExecutionPolicy', 'Bypass'] if os.name == 'nt' else []
        for mode in scenarios:
            output = root / mode
            if mode == 'existing-output':
                output.mkdir()
                (output / 'keep.txt').write_text('retain me')
            stage = 'All' if mode in ['capture', 'no-log', 'invalid-log'] else 'App'
            result = subprocess.run(
                [pwsh, '-NoProfile', *policy_args, '-File', str(collector), '-AdbPath', str(fake),
                 '-OutputDirectory', str(output), '-Stage', stage],
                input='\n5.0\nunknown\n20:00-20:01 UTC\n', text=True,
                capture_output=True, timeout=30,
                env={**environment, 'WHOOP_TEST_SCENARIO': mode},
            )
            success = mode in ['app', 'capture', 'no-log', 'invalid-log']
            assert (result.returncode == 0) == success, (mode, result.stdout, result.stderr)
            share = output / 'whoop-review-before-sharing.zip'
            if not success:
                assert not share.exists(), mode
                if mode == 'existing-output':
                    assert (output / 'keep.txt').read_text() == 'retain me'
                print(f'PASS {mode}')
                continue
            with zipfile.ZipFile(share) as z:
                names = z.namelist()
                assert not any('bugreport' in n or 'private-' in n for n in names), names
                manifest = json.loads(z.read('manifest.json'))
                assert len(manifest['apk_sources']) == 2
                assert 'PRIVATE FULL DUMP' not in json.dumps(manifest)
                assert 'TESTPIXEL' not in json.dumps(manifest)
                for item in manifest['files']:
                    data = z.read(item['path'])
                    assert hashlib.sha256(data).hexdigest() == item['sha256']
                    assert len(data) == item['size_bytes']
                expected = {'app': 'not_requested', 'capture': 'snoop_files_collected_content_unverified',
                            'no-log': 'no_usable_snoop_log_found', 'invalid-log': 'no_usable_snoop_log_found'}[mode]
                assert manifest['capture_status'] == expected
                assert len(manifest['bluetooth_logs']) == (2 if mode == 'capture' else 0)
            assert not (root / 'escape').exists()
            if stage == 'All':
                assert (output / 'private-do-not-share/bugreport.zip').exists()
            print(f'PASS {mode}')
    print(f'{len(scenarios)} simulated acceptance scenarios passed; real device untested.')


if __name__ == '__main__':
    main()
