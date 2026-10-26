#requires -Version 5.1
<#
Collect an installed WHOOP APK set and/or a manually recorded Bluetooth sync.
Requires existing Android platform-tools. No installation, device settings
changes, rooting, authentication interception or automatic upload is performed.
ADB may start its local server. Bug report generation can take several minutes.
#>
[CmdletBinding()]
param(
    [string]$AdbPath,
    [string]$Serial,
    [ValidatePattern('^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$')]
    [string]$PackageId,
    [ValidateSet('All', 'App', 'Capture')]
    [string]$Stage = 'All',
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Adb {
    param([string[]]$Arguments)
    # Combine native diagnostic streams without turning ordinary stderr into a
    # terminating PowerShell 5.1 error. The native exit code remains authoritative.
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $script:Adb @Arguments 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $saved }
    if ($code -ne 0) {
        throw "ADB failed (exit $code): $($lines -join [Environment]::NewLine)"
    }
    return $lines
}

function Invoke-DeviceAdb {
    param([string[]]$Arguments)
    Invoke-Adb -Arguments (@('-s', $script:SelectedSerial) + $Arguments)
}

function Write-JsonFile {
    param($Value, [string]$Path)
    $json = ConvertTo-Json -InputObject $Value -Depth 12
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

try {
    if ($AdbPath) {
        $script:Adb = (Resolve-Path -LiteralPath $AdbPath).Path
    } elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'platform-tools/adb.exe')) {
        $script:Adb = Join-Path $PSScriptRoot 'platform-tools/adb.exe'
    } elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'adb.exe')) {
        $script:Adb = Join-Path $PSScriptRoot 'adb.exe'
    } else {
        $found = Get-Command adb -CommandType Application -ErrorAction SilentlyContinue
        if (-not $found) {
            throw 'ADB not found. Extract Google platform-tools beside this script, or pass -AdbPath C:\path\platform-tools\adb.exe. See README.md.'
        }
        $script:Adb = $found.Source
    }

    $adbVersion = @(Invoke-Adb -Arguments @('version'))
    $listing = @(Invoke-Adb -Arguments @('devices', '-l'))
    $devices = @($listing | ForEach-Object {
        if ($_ -match '^([^\s]+)\s+(device|unauthorized|offline)(?:\s|$)') {
            [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2] }
        }
    })
    if ($Serial) {
        $selected = @($devices | Where-Object { $_.Serial -ceq $Serial })
    } else {
        $selected = $devices
    }
    if ($selected.Count -eq 0) {
        throw 'No matching Android device. Connect the unlocked Pixel with a USB data cable, enable USB debugging, and rerun. Check the Google USB driver if needed.'
    }
    if ($selected.Count -ne 1) {
        throw 'Multiple Android devices are connected. Rerun with -Serial using the desired serial from adb devices -l.'
    }
    if ($selected[0].State -ne 'device') {
        throw "Device is $($selected[0].State). Unlock the Pixel and approve its USB debugging prompt; reconnect if offline, then rerun."
    }
    $script:SelectedSerial = $selected[0].Serial

    if (-not $OutputDirectory) {
        $desktop = [Environment]::GetFolderPath('Desktop')
        if (-not $desktop) { $desktop = (Get-Location).Path }
        $suffix = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
        $OutputDirectory = Join-Path $desktop "WHOOP-$suffix"
    }
    $root = [IO.Path]::GetFullPath($OutputDirectory)
    if (Test-Path -LiteralPath $root) { throw "Output already exists: $root. Choose a fresh directory." }
    $null = New-Item -ItemType Directory -Path $root
    $bundle = Join-Path $root 'review-before-sharing'
    $null = New-Item -ItemType Directory -Path $bundle
    $metadata = [ordered]@{
        schema_version = 1
        collected_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
        stage = $Stage
        adb_version = $adbVersion
        phone_model = (Invoke-DeviceAdb -Arguments @('shell', 'getprop', 'ro.product.model')) -join ''
        android_release = (Invoke-DeviceAdb -Arguments @('shell', 'getprop', 'ro.build.version.release')) -join ''
        android_api = (Invoke-DeviceAdb -Arguments @('shell', 'getprop', 'ro.build.version.sdk')) -join ''
        package_id = $null
        app_version_observations = @()
        band_model = $null
        band_firmware = $null
        apk_sources = @()
        bluetooth_logs = @()
        capture_status = 'not_requested'
        limitations = @('No protocol decoding or runtime method attribution has been performed.', 'Bluetooth logs may contain personal data and other device traffic. Review before sharing.')
    }

    if ($Stage -in @('All', 'App')) {
        $packages = @(Invoke-DeviceAdb -Arguments @('shell', 'pm', 'list', 'packages') | ForEach-Object {
            if ($_ -match '^package:([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+)$') { $Matches[1] }
        })
        if ($PackageId) {
            if ($PackageId -cnotin $packages) { throw "Package $PackageId is not installed on the selected device." }
        } else {
            $candidates = @($packages | Where-Object { $_ -match 'whoop' })
            if ($candidates.Count -ne 1) {
                throw "Expected one WHOOP package, found $($candidates.Count). Rerun with -PackageId from adb shell pm list packages. Candidates: $($candidates -join ', ')"
            }
            $PackageId = $candidates[0]
        }
        $metadata.package_id = $PackageId
        $metadata.app_version_observations = @(Invoke-DeviceAdb -Arguments @('shell', 'dumpsys', 'package', $PackageId) |
            Where-Object { $_ -match '^\s*version(?:Name|Code)=' } | ForEach-Object { $_.Trim() })
        $paths = @(Invoke-DeviceAdb -Arguments @('shell', 'pm', 'path', $PackageId) | ForEach-Object {
            if ($_ -match '^package:(/.+\.apk)$') { $Matches[1] }
        } | Select-Object -Unique)
        if ($paths.Count -eq 0) { throw 'No APK paths returned; no app acquisition is claimed.' }
        $apkDirectory = Join-Path $bundle 'apks'
        $null = New-Item -ItemType Directory -Path $apkDirectory
        $index = 0
        foreach ($source in $paths) {
            # Generated names avoid target-supplied paths and collisions between splits.
            $name = '{0:D3}.apk' -f $index
            $destination = Join-Path $apkDirectory $name
            Write-Host "Copying APK $($index + 1) of $($paths.Count)..."
            $null = Invoke-DeviceAdb -Arguments @('pull', $source, $destination)
            if (-not (Test-Path -LiteralPath $destination) -or (Get-Item -LiteralPath $destination).Length -eq 0) {
                throw "ADB did not produce a nonempty APK: $name"
            }
            $metadata.apk_sources += [ordered]@{ file = "apks/$name"; device_path = $source }
            $index++
        }
    }

    if ($Stage -in @('All', 'Capture')) {
        Write-Host ''
        Write-Host 'On the Pixel: enable Developer options > Bluetooth HCI snoop log.'
        Write-Host 'Toggle Bluetooth off/on, allow WHOOP to reconnect, then open WHOOP and let one normal sync complete.'
        Write-Host 'Note sync start/end times with time zone. Leave the phone connected.'
        $metadata.capture_instructions_shown_utc = [DateTimeOffset]::UtcNow.ToString('o')
        $null = Read-Host 'Press Enter AFTER the sync completes (Ctrl+C to stop)'
        $metadata.user_confirmed_sync_complete_utc = [DateTimeOffset]::UtcNow.ToString('o')
        $metadata.band_model = Read-Host 'WHOOP band model (Enter if unknown)'
        $metadata.band_firmware = Read-Host 'Band firmware version (Enter if unknown)'
        $metadata.user_sync_times = Read-Host 'Sync start/end times and time zone (Enter if unknown)'
        $private = Join-Path $root 'private-do-not-share'
        $null = New-Item -ItemType Directory -Path $private
        $bugreport = Join-Path $private 'bugreport.zip'
        Write-Host 'Collecting the bug report; this may take several minutes...'
        $null = Invoke-DeviceAdb -Arguments @('bugreport', $bugreport)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($bugreport)
        try {
            $entries = @($archive.Entries | Where-Object {
                # Only known raw snoop-log names, not arbitrary Bluetooth files.
                $_.FullName -match '(?i)(?:^|/)(?:btsnoop_hci\.log(?:\.last)?|btsnoop\.log)$'
            })
            if ($entries.Count -gt 16) { throw 'Unexpected number of Bluetooth logs; inspect the private bug report manually.' }
            $total = 0L
            $index = 0
            foreach ($entry in $entries) {
                $total += $entry.Length
                if ($total -gt 536870912) { throw 'Bluetooth logs exceed the 512 MiB extraction budget. Inspect the private bug report manually.' }
                if ($entry.Length -eq 0) { continue }
                $name = 'bluetooth-{0:D2}.log' -f $index
                $destination = Join-Path $bundle $name
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $false)
                $stream = [IO.File]::OpenRead($destination)
                try {
                    $header = New-Object byte[] 8
                    $read = $stream.Read($header, 0, 8)
                } finally { $stream.Dispose() }
                $valid = $read -eq 8 -and [Text.Encoding]::ASCII.GetString($header) -ceq "btsnoop`0"
                if (-not $valid) {
                    Remove-Item -LiteralPath $destination
                    $metadata.limitations += "Entry $($entry.FullName) was not a recognized btsnoop recording and was excluded."
                    continue
                }
                $metadata.bluetooth_logs += [ordered]@{ file = $name; bugreport_entry = $entry.FullName }
                $index++
            }
        } finally { $archive.Dispose() }
        if ($metadata.bluetooth_logs.Count -gt 0) {
            $metadata.capture_status = 'snoop_files_collected_content_unverified'
        } else {
            $metadata.capture_status = 'no_usable_snoop_log_found'
            $metadata.limitations += 'No usable raw snoop log in the bug report. Logging may be disabled, filtered or omitted by this Android build. Text btsnooz extraction may be needed.'
            Write-Warning 'No usable Bluetooth log found. The APKs can still be analysed. Keep the private bug report locally for troubleshooting.'
        }
        Write-Host 'You can now disable Bluetooth HCI snoop logging on the Pixel.'
    }

    $metadata.files = @(Get-ChildItem -LiteralPath $bundle -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            path = $_.FullName.Substring($bundle.Length + 1).Replace('\', '/')
            size_bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    Write-JsonFile -Value $metadata -Path (Join-Path $bundle 'manifest.json')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = Join-Path $root 'whoop-review-before-sharing.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($bundle, $zip)
    Write-Host ''
    Write-Host "Collection complete: $zip"
    Write-Host "Capture status: $($metadata.capture_status)"
    Write-Host 'Review the ZIP before attaching it to the chat. It contains APKs, selected logs and metadata; nothing was uploaded.'
    Write-Host 'The full bug report stays in private-do-not-share and is NOT in the ZIP.'
    exit 0
} catch {
    [Console]::Error.WriteLine("Collection stopped: $($_.Exception.Message)")
    [Console]::Error.WriteLine('Existing partial files were retained locally. No successful collection or upload is claimed. Rerun into a fresh output directory.')
    exit 1
}
