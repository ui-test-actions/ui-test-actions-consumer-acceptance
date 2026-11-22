$ErrorActionPreference = 'Stop'
$inputDir = Join-Path $env:RUNNER_TEMP 'pos-windows-input'
gh run download -R kira-manga/test 44257616578 -n pos-windows-msi-44257616578-1 -D $inputDir
if ($LASTEXITCODE -ne 0) { throw 'The retained POS MSI artifact could not be downloaded.' }
$msi = @(Get-ChildItem $inputDir -Recurse -Filter '*.msi')
if ($msi.Count -ne 1) { throw 'Expected exactly one POS MSI.' }
$source = Get-ChildItem $inputDir -Recurse -Filter 'SOURCE-REVISION.txt' | Select-Object -First 1
if ($source) { Get-Content $source.FullName }
$hash = (Get-FileHash $msi[0].FullName -Algorithm SHA256).Hash
if ($hash -ne '53AAE7DE35561F4B92C3FDFED5F13A1E61BD4EF32F82FA5E8549BCD00C74B58C') { throw 'Unexpected MSI hash.' }
Write-Host "Verified MSI SHA-256 $hash"
$log = Join-Path $env:RUNNER_TEMP 'pos-msi.log'
$install = Start-Process msiexec.exe -ArgumentList "/i `"$($msi[0].FullName)`" /qn /norestart /l*v `"$log`"" -Wait -PassThru
if ($install.ExitCode -notin @(0, 3010)) { throw "MSI install failed with $($install.ExitCode)" }
$roots = @(
    $env:ProgramFiles
    ${env:ProgramFiles(x86)}
    (Join-Path $env:LOCALAPPDATA 'Programs')
    $env:LOCALAPPDATA
)
$locations = @(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object DisplayName -Match 'ukkera' | Select-Object -ExpandProperty InstallLocation)
$scopes = @(foreach ($root in $roots) {
    if ($root -and (Test-Path $root)) {
        Get-ChildItem $root -Directory | Where-Object Name -Match 'ukkera|^pos$' | Select-Object -ExpandProperty FullName
    }
})
$apps = @(foreach ($folder in ($locations + $scopes | Where-Object { $_ -and (Test-Path $_) } | Sort-Object -Unique)) {
    Get-ChildItem $folder -Recurse -Filter '*.exe' | Where-Object { $_.Name -Match 'ukkera|^pos\.exe$' }
})
$apps = @($apps | Sort-Object FullName -Unique)
if ($apps.Count -ne 1) {
    Select-String -Path $log -Pattern 'INSTALLDIR|INSTALLFOLDER|ApplicationFolder|UkkeraPOS.exe' | Select-Object -Last 24
    throw "Expected one installed POS launcher, found $($apps.Count)."
}
"POS_EXE=$($apps[0].FullName)" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
