# Install the exact selected public MSI on a disposable GitHub-hosted VM.
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:CI -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') { throw 'Requires disposable GitHub-hosted runner' }
$tag = $env:RELEASE_TAG
if ($tag -notmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw 'Invalid stable release tag' }
$version = $tag.Substring(1)
$name = "Auto.Clicker_${version}_x64_en-US.msi"
$release = gh api "repos/$env:GITHUB_REPOSITORY/releases/tags/$tag" | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $release.tag_name -cne $tag -or $release.draft -or $release.prerelease) { throw 'Public release metadata unavailable' }
$asset = @($release.assets | Where-Object { $_.name -ceq $name })
if ($asset.Count -ne 1 -or $asset[0].digest -notmatch '^sha256:[0-9a-f]{64}$') { throw 'Missing public asset digest' }
$msi = Join-Path $env:RUNNER_TEMP $name
Invoke-WebRequest "https://github.com/$env:GITHUB_REPOSITORY/releases/download/$tag/$name" -OutFile $msi
$expected = $asset[0].digest.Substring(7).ToUpperInvariant()
if ((Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash -cne $expected) { throw "Public $tag MSI SHA-256 mismatch" }
$install = Start-Process msiexec.exe -ArgumentList '/i',"`"$msi`"",'/qn','/norestart' -Wait -PassThru
if ($install.ExitCode -ne 0) { throw "Public MSI installation failed: $($install.ExitCode)" }
$exe = Join-Path $env:ProgramFiles 'Auto Clicker\auto-clicker.exe'
if (-not (Test-Path -LiteralPath $exe) -or (Get-Item -LiteralPath $exe).VersionInfo.FileVersion -notmatch "^$([regex]::Escape($version))(\.0)?$") { throw "Installed binary is not $tag" }
"AUTOCLICKER_TEST_EXE=$exe" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
Write-Host "Installed publicly released $tag MSI, SHA-256 $expected"
