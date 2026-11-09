$ErrorActionPreference = 'Stop'
$tmp = Join-Path $env:RUNNER_TEMP 'auto-clicker-update-test'
$root = Get-Location
$manifest = @{
  version = '0.1.1'; notes = 'CI-only update'; pub_date = '2026-01-01T00:00:00Z';
  platforms = @{ 'windows-x86_64' = @{ signature = (Get-Content "$tmp/update.msi.sig" -Raw).Trim(); url = 'http://127.0.0.1:18173/update.msi' } }
} | ConvertTo-Json -Depth 5
Set-Content "$tmp/latest.json" $manifest -Encoding utf8
$server = Start-Process python -ArgumentList '-m','http.server','18173','--bind','127.0.0.1','--directory',"`"$tmp`"" -PassThru -WindowStyle Hidden -RedirectStandardOutput "$tmp/server.out" -RedirectStandardError "$tmp/server.err"
Set-Content "$tmp/server.pid" $server.Id
$url = 'https://github.com/uulab-official/auto-clicker/releases/download/v0.1.0/Auto-Clicker_0.1.0_x64.msi'
Invoke-WebRequest $url -OutFile "$tmp/published.msi"
$file = Get-Item "$tmp/published.msi"
$header = ([System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($file.FullName)[0..7]))
Write-Host "Downloaded MSI size: $($file.Length); header: $header; SHA256: $((Get-FileHash $file.FullName -Algorithm SHA256).Hash)"
if ($header -ne 'D0-CF-11-E0-A1-B1-1A-E1') { throw 'Downloaded file is not a valid MSI compound file' }
$logPath = Join-Path $tmp 'msi-install.log'
$p = Start-Process msiexec.exe -ArgumentList '/i',"`"$($file.FullName)`"",'/qn','/norestart','/L*V',"`"$logPath`"" -Wait -PassThru
if ($p.ExitCode -ne 0) {
  if (Test-Path $logPath) { Get-Content $logPath | Write-Host }
  throw "Published MSI install failed: $($p.ExitCode)"
}
$locations = @("$env:ProgramFiles\Auto Clicker", "${env:ProgramFiles(x86)}\Auto Clicker", "$env:LOCALAPPDATA\Programs\Auto Clicker")
$exe = $null
foreach ($location in $locations) {
  if (Test-Path $location) { $exe = Get-ChildItem $location -Filter 'auto-clicker.exe' -Recurse | Select-Object -First 1; if ($exe) { break } }
}
if (-not $exe) { throw 'Installed executable not found' }
Write-Host "Published MSI installed executable: $($exe.FullName)"
# WiX can modify executable resources during bundling; compare against the
# binary extracted from the exact signed candidate MSI, not the pre-bundle exe.
$extractDir = Join-Path $tmp 'candidate-extracted'
New-Item -ItemType Directory -Force $extractDir | Out-Null
$updateMsi = (Get-Item "$tmp/update.msi").FullName
$extractLog = Join-Path $tmp 'msi-extract.log'
$extract = Start-Process msiexec.exe -ArgumentList '/a',"`"$updateMsi`"",'/qn',"TARGETDIR=`"$extractDir`"",'/L*V',"`"$extractLog`"" -Wait -PassThru
if ($extract.ExitCode -ne 0) { if (Test-Path $extractLog) { Get-Content $extractLog | Write-Host }; throw "Candidate MSI extraction failed: $($extract.ExitCode)" }
$payload = Get-ChildItem $extractDir -Filter 'auto-clicker.exe' -Recurse | Select-Object -First 1
if (-not $payload) { throw 'Candidate MSI does not contain auto-clicker.exe' }
Set-Content "$tmp/payload-sha256.txt" (Get-FileHash $payload.FullName -Algorithm SHA256).Hash
Set-Content "$tmp/installed-path.txt" $exe.FullName
Copy-Item "$root/src-tauri/target/release/auto-clicker.exe" $exe.FullName -Force
Start-Process $exe.FullName | Out-Null
Write-Host 'Launched test-instrumented installed app; waiting for update in the same step.'
& .github/scripts/windows-update-test/verify.ps1
