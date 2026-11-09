$ErrorActionPreference = 'Stop'
$tmp = Join-Path $env:RUNNER_TEMP 'auto-clicker-update-test'
try {
  $exe = (Get-Content "$tmp/installed-path.txt" -Raw).Trim()
  $candidateHash = (Get-FileHash "$tmp/candidate.exe" -Algorithm SHA256).Hash
  $deadline = (Get-Date).AddMinutes(4)
  $currentHash = ''
  do {
    Start-Sleep -Seconds 3
    $log = if (Test-Path "$tmp/events.log") { Get-Content "$tmp/events.log" -Raw } else { '' }
    if ($log -match 'error:') { throw "Updater command failed: $log" }
    try { if (Test-Path $exe) { $currentHash = (Get-FileHash $exe -Algorithm SHA256).Hash } } catch { $currentHash = '' }
    if ($currentHash -eq $candidateHash) { break }
  } while ((Get-Date) -lt $deadline)
  if ($currentHash -ne $candidateHash) {
    foreach ($diagnostic in @('events.log', 'server.err', 'update-install.log')) {
      if (Test-Path "$tmp/$diagnostic") { Write-Host "--- $diagnostic ---"; Get-Content "$tmp/$diagnostic" | Write-Host }
    }
    throw 'Installed executable was not updated'
  }
  if ($log -notmatch 'update found 0.1.1' -or $log -notmatch 'install requested') { throw "Missing updater evidence: $log" }
  Write-Host 'Published MSI installed; test-instrumented app checked, verified and installed the signed 0.1.1 MSI.'
} finally {
  if (Test-Path "$tmp/server.pid") { Stop-Process -Id ([int](Get-Content "$tmp/server.pid" -Raw)) -Force -ErrorAction SilentlyContinue }
}
