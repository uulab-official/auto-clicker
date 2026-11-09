$ErrorActionPreference = 'Stop'
$tmp = Join-Path $env:RUNNER_TEMP 'auto-clicker-update-test'
try {
  $exe = (Get-Content "$tmp/installed-path.txt" -Raw).Trim()
  $candidateHash = (Get-Content "$tmp/payload-sha256.txt" -Raw).Trim()
  $deadline = (Get-Date).AddMinutes(4)
  $installed = $false
  do {
    Start-Sleep -Seconds 3
    $log = if (Test-Path "$tmp/events.log") { Get-Content "$tmp/events.log" -Raw } else { '' }
    if ($log -match 'error:') { throw "Updater command failed: $log" }
    $version = ''; $currentHash = ''
    try { if (Test-Path $exe) { $version = (Get-Item $exe).VersionInfo.FileVersion; $currentHash = (Get-FileHash $exe -Algorithm SHA256).Hash } } catch { $version = ''; $currentHash = '' }
    $msiLog = if (Test-Path "$tmp/update-install.log") { Get-Content "$tmp/update-install.log" -Raw -ErrorAction SilentlyContinue } else { '' }
    if ($currentHash -eq $candidateHash -and $version -match '^0\.1\.1(\.0)?$' -and $msiLog -match 'Product Version: 0\.1\.1\..*Installation success or error status: 0') { $installed = $true; break }
  } while ((Get-Date) -lt $deadline)
  if (-not $installed) {
    Write-Host "Installed executable version: $version"
    if (Test-Path $exe) { Write-Host "Installed SHA256: $((Get-FileHash $exe -Algorithm SHA256).Hash); MSI payload SHA256: $candidateHash" }
    foreach ($diagnostic in @('events.log', 'server.err', 'update-install.log')) {
      if (Test-Path "$tmp/$diagnostic") { Write-Host "--- $diagnostic ---"; Get-Content "$tmp/$diagnostic" | Write-Host }
    }
    throw 'Installed executable version and successful MSI log were not both observed'
  }
  if ($log -notmatch 'update found 0.1.1' -or $log -notmatch 'install requested') { throw "Missing updater evidence: $log" }
  Write-Host "Verified installed executable file version: $version; SHA256 matches signed MSI payload: $currentHash"
  $relaunch = Start-Process $exe -PassThru
  Start-Sleep -Seconds 5
  if ($relaunch.HasExited) { throw "Updated app exited immediately with code $($relaunch.ExitCode)" }
  Stop-Process -Id $relaunch.Id -Force
  Write-Host 'Updated application launched successfully.'
  Write-Host 'Published MSI installed; test-instrumented app checked, verified and installed the signed 0.1.1 MSI.'
} finally {
  if (Test-Path "$tmp/server.pid") { Stop-Process -Id ([int](Get-Content "$tmp/server.pid" -Raw)) -Force -ErrorAction SilentlyContinue }
}
