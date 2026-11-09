$ErrorActionPreference = 'Stop'
$tmp = Join-Path $env:RUNNER_TEMP 'auto-clicker-update-test'
$root = Get-Location
$manifest = @{
  version = '0.1.1'; notes = 'CI-only update'; pub_date = '2026-01-01T00:00:00Z';
  platforms = @{ 'windows-x86_64' = @{ signature = (Get-Content "$tmp/update.msi.sig" -Raw).Trim(); url = 'http://127.0.0.1:18173/update.msi' } }
} | ConvertTo-Json -Depth 5
Set-Content "$tmp/latest.json" $manifest -Encoding utf8
$server = Start-Process python -ArgumentList '-m','http.server','18173','--bind','127.0.0.1','--directory',"`"$tmp`"" -PassThru -NoNewWindow
try {
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
  Copy-Item "$root/src-tauri/target/release/auto-clicker.exe" $exe.FullName -Force
  $candidateHash = (Get-FileHash "$tmp/candidate.exe" -Algorithm SHA256).Hash
  Start-Process $exe.FullName | Out-Null
  $deadline = (Get-Date).AddMinutes(3)
  do {
    Start-Sleep -Seconds 3
    $log = if (Test-Path "$tmp/events.log") { Get-Content "$tmp/events.log" -Raw } else { '' }
    if ($log -match 'error:') { throw "Updater command failed: $log" }
    $currentHash = if (Test-Path $exe.FullName) { (Get-FileHash $exe.FullName -Algorithm SHA256).Hash } else { '' }
    if ($currentHash -eq $candidateHash) { break }
  } while ((Get-Date) -lt $deadline)
  if ($currentHash -ne $candidateHash) { throw "Installed executable was not updated. Events: $log" }
  if ($log -notmatch 'update found 0.1.1' -or $log -notmatch 'install requested') { throw "Missing updater evidence: $log" }
  Write-Host 'Published MSI installed; test-instrumented app checked, verified and installed the signed 0.1.1 MSI.'
} finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
