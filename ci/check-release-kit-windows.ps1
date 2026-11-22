$ErrorActionPreference = 'Stop'
$stage = Join-Path $env:RUNNER_TEMP 'mrk-windows'
$evidence = Join-Path $env:RUNNER_TEMP 'mrk-evidence'
New-Item -ItemType Directory -Path $evidence | Out-Null
gh run download -R Apdelrahman1911/mobile-release-kit 43743261196 -n windows-native-transaction-build -D $stage
if ($LASTEXITCODE -ne 0) { throw 'Windows candidate download failed.' }
$package = Join-Path $stage 'msi\MobileReleaseKit-NONSHIPPING.msi'
$sha = (Get-FileHash $package -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sha -ne 'd41a503d928fbb0d7e9c160ac8e1f41dcd5f6fecdc2d5df9c3ccd82f06a43ca1') { throw 'Unexpected package hash.' }
$log = Join-Path $stage 'installer.log'
$result = Start-Process msiexec.exe -ArgumentList "/i `"$package`" /qn /norestart /l*v `"$log`"" -PassThru -Wait
$guard = Select-String -SimpleMatch 'NONSHIPPING: native transaction owner and Windows installed consumer are unqualified.' -Path $log
if ($result.ExitCode -ne 1603 -or !$guard) { throw "Expected the documented package gate, got exit $($result.ExitCode)." }
[ordered]@{ sha256=$sha; exit=$result.ExitCode; shipping_gate_observed=$true } |
    ConvertTo-Json | Out-File (Join-Path $evidence 'gate.json')
