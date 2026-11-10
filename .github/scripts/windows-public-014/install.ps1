# Install only the exact published v0.1.4 MSI on a disposable GitHub VM.
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:CI -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') { throw 'Requires disposable GitHub-hosted runner' }
$msi = Join-Path $env:RUNNER_TEMP 'Auto.Clicker_0.1.4_x64_en-US.msi'
Invoke-WebRequest 'https://github.com/uulab-official/auto-clicker/releases/download/v0.1.4/Auto.Clicker_0.1.4_x64_en-US.msi' -OutFile $msi
$expected = 'FC91F176664B8F47283B45D0798BCA2BE865D4DF603A9DF6ED13BEFD5F70A9F6'
if ((Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash -cne $expected) { throw 'Public v0.1.4 MSI SHA-256 mismatch' }
$install = Start-Process msiexec.exe -ArgumentList '/i',"`"$msi`"",'/qn','/norestart' -Wait -PassThru
if ($install.ExitCode -ne 0) { throw "Public MSI installation failed: $($install.ExitCode)" }
$exe = Join-Path $env:ProgramFiles 'Auto Clicker\auto-clicker.exe'
if (-not (Test-Path -LiteralPath $exe) -or (Get-Item -LiteralPath $exe).VersionInfo.FileVersion -notmatch '^0\.1\.4(\.0)?$') { throw 'Installed binary is not v0.1.4' }
"AUTOCLICKER_TEST_EXE=$exe" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
Write-Host "Installed publicly released v0.1.4 MSI, SHA-256 $expected"
