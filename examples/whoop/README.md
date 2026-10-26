# Collect WHOOP evidence on Windows

This standalone PowerShell helper copies the installed WHOOP APK set and
collects a user-triggered sync recording through existing Android platform-tools.
It does not need REA or Java on the Windows computer. It does not install apps,
change phone settings, root the device, or upload files. ADB may start its local
server; generating the bug report reads broader device diagnostics into a local
private directory. The sharing ZIP excludes the full bug report.

## Run

1. Download and extract Google's
   [platform-tools for Windows](https://dl.google.com/android/repository/platform-tools-latest-windows.zip).
   Put the resulting `platform-tools` directory beside `Collect-Whoop.ps1`.
2. On the Pixel, enable Developer options and USB debugging. Connect with a USB
   data cable, unlock it and accept the USB debugging prompt for your computer.
3. Open PowerShell in this folder and run:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Collect-Whoop.ps1
   ```

   The execution-policy option applies only to this process. No administrator
   access or persistent execution-policy change is required. If company policy
   blocks scripts, use an approved computer or ask its administrator.
4. Follow the prompt to enable Bluetooth HCI snoop logging, restart Bluetooth,
   and complete a normal WHOOP sync. Press Enter only after syncing completes.
5. Review `whoop-review-before-sharing.zip` in the new `WHOOP-...` folder on
   your Desktop, then attach that ZIP to the investigation chat. The script
   never sends files automatically. Bluetooth logs can contain personal data
   and unrelated devices' traffic. Keep `private-do-not-share` on your computer.

If Windows does not detect the Pixel, check the USB data cable and the
[Google USB driver](https://developer.android.com/studio/run/win-usb).
For `unauthorized`, unlock the phone and approve the prompt, then rerun.

## Options

```powershell
# Use an existing ADB installation; collect only the installed APKs first.
.\Collect-Whoop.ps1 -AdbPath 'C:\Android\platform-tools\adb.exe' -Stage App

# Collect only the recording later (new output directory each time).
.\Collect-Whoop.ps1 -AdbPath 'C:\Android\platform-tools\adb.exe' -Stage Capture

# Select explicitly if more than one device or WHOOP package is found.
.\Collect-Whoop.ps1 -Serial 'OBSERVED_SERIAL' -PackageId 'OBSERVED.PACKAGE.ID'
```

`-OutputDirectory` optionally selects a fresh directory. Existing directories
are refused. Failed runs retain partial files and exit with status 1. Native
ADB commands run synchronously; bug-report collection can take minutes and
Ctrl+C cancels the foreground script. The script leaves the ADB server alone.

## Results and limits

- APKs get numbered local filenames; `manifest.json` maps each to its device
  source path, records observed version lines, and hashes the collected files.
  Split APKs are preserved separately, not merged.
- Recognized raw btsnoop logs are extracted under generated filenames, bounded
  to 16 candidate entries and 512 MiB total declared uncompressed log size.
  Header recognition does not prove packet completeness or a WHOOP connection.
- No matching log is explicitly reported as `no_usable_snoop_log_found`;
  it is not treated as a successful Bluetooth recording. Android builds may
  omit raw logs or retain only filtered/text data. See Android's
  [capture guidance](https://source.android.com/docs/core/connect/bluetooth/verifying_debugging).
- The phone serial, entire installed-package list and full package dump are
  not written into the sharing manifest. APK device paths and diagnostic
  version lines are preserved for provenance.
- No message decoding, WHOOP protocol support or real-device compatibility
  is established by the helper alone.

See the repository's
[investigation workflow](https://github.com/LIAMSTAINTON21/rea/blob/main/docs/whoop-sync-investigation.md)
for the analysis procedure (available after the investigation changes are merged).

## Verification

The collector was exercised in PowerShell 7 on Linux and Windows PowerShell 5.1
with a simulated ADB:
APK and split copying, normal capture packaging, absent/invalid snoop logs,
missing/unauthorized/multiple devices, ambiguous packages, missing APK paths,
copy failure, and refusal to overwrite an existing output directory. The checks
also verify hashes, exclusion of the private bug report and safe generated
filenames for archive entries containing parent-directory segments.

Run those checks with Python 3 and an existing PowerShell:

```sh
python3 examples/whoop/test_collector.py /absolute/path/to/pwsh
```

On Windows, pass `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`
as the PowerShell executable. The harness uses a CMD shim for the simulated ADB
and applies an execution-policy override only to the test process.

All eleven scenarios passed in Windows PowerShell 5.1. A real Pixel has not yet
been acquired; simulation does not establish real-device acquisition or protocol
compatibility.
