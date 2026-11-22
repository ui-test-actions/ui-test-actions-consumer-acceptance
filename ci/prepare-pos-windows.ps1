$ErrorActionPreference = 'Stop'
$inputDir = Join-Path $env:RUNNER_TEMP 'pos-windows-input'
gh run download -R kira-manga/test 44257616578 -n pos-windows-msi-44257616578-1 -D $inputDir
if ($LASTEXITCODE -ne 0) { throw 'The retained POS MSI artifact could not be downloaded.' }
$msi = @(Get-ChildItem $inputDir -Recurse -Filter '*.msi')
if ($msi.Count -ne 1) { throw 'Expected exactly one POS MSI.' }
$source = Get-ChildItem $inputDir -Recurse -Filter 'SOURCE-REVISION.txt' | Select-Object -First 1
if ($source) { Get-Content $source.FullName }
Get-FileHash $msi[0].FullName -Algorithm SHA256 | Format-Table -AutoSize
$log = Join-Path $env:RUNNER_TEMP 'pos-msi.log'
$install = Start-Process msiexec.exe -ArgumentList "/i `"$($msi[0].FullName)`" /qn /norestart /l*v `"$log`"" -Wait -PassThru
if ($install.ExitCode -notin @(0, 3010)) { throw "MSI install failed with $($install.ExitCode)" }
$apps = @(Get-ChildItem $env:ProgramFiles -Directory | Where-Object Name -Match 'ukkera|^pos$' |
    Get-ChildItem -Recurse -Filter '*.exe' | Where-Object { $_.Name -Match 'ukkera|^pos\.exe$' })
if ($apps.Count -ne 1) { throw "Expected one installed POS launcher, found $($apps.Count)." }
"POS_EXE=$($apps[0].FullName)" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
