# Runs only in an isolated GitHub-hosted Windows VM. No released binary is modified.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$tmp = Join-Path $env:RUNNER_TEMP 'public-auto-clicker-update'
New-Item -Type Directory -Force $tmp | Out-Null
$target = $env:EXPECTED_UPDATE_VERSION
$probe = $env:PROBE_ONLY -eq 'true'
if ($target -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid expected version' }
if (-not $probe) {
  $manifest = Invoke-RestMethod 'https://github.com/uulab-official/auto-clicker/releases/latest/download/latest.json'
  if ($manifest.version -ne $target) { throw "Public latest is $($manifest.version), expected $target" }
}
$oldMsi = Join-Path $tmp 'old.msi'
Invoke-WebRequest 'https://github.com/uulab-official/auto-clicker/releases/download/v0.1.1/Auto.Clicker_0.1.1_x64_en-US.msi' -OutFile $oldMsi
if ((Get-FileHash $oldMsi -Algorithm SHA256).Hash -ne '12741B32513AF6649F3A25F14A79010DDC172E91FFDC1A8426268143A8550EF5') { throw 'Baseline MSI does not match the v0.1.1 release asset digest' }
$p = Start-Process msiexec.exe -ArgumentList '/i',"`"$oldMsi`"",'/qn','/norestart' -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "v0.1.1 installation failed: $($p.ExitCode)" }
$exe = Join-Path $env:ProgramFiles 'Auto Clicker\auto-clicker.exe'
if (-not (Test-Path $exe)) { throw 'Installed application not found' }
$oldVersion = (Get-Item $exe).VersionInfo.FileVersion
if ($oldVersion -notmatch '^0\.1\.1(\.0)?$') { throw "Unexpected baseline file version: $oldVersion" }
Write-Host "Installed unmodified public application: $oldVersion"
# Independently obtain the publicly advertised MSI to compare the installed
# executable with its exact embedded payload after the app has updated itself.
if (-not $probe) {
$candidate = Join-Path $tmp 'public-update.msi'
Invoke-WebRequest $manifest.platforms.'windows-x86_64'.url -Headers @{ Accept = 'application/octet-stream' } -OutFile $candidate
$magic = [BitConverter]::ToString([IO.File]::ReadAllBytes($candidate)[0..7])
if ($magic -ne 'D0-CF-11-E0-A1-B1-1A-E1') { throw 'Public Windows updater payload is not an MSI' }
$extract = Join-Path $tmp 'extracted'
New-Item -Type Directory -Force $extract | Out-Null
$p = Start-Process msiexec.exe -ArgumentList '/a',"`"$candidate`"",'/qn',"TARGETDIR=`"$extract`"" -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Public MSI extraction failed: $($p.ExitCode)" }
$payload = Get-ChildItem $extract -Filter auto-clicker.exe -Recurse | Select-Object -First 1
if (-not $payload) { throw 'Public MSI has no executable' }
$expectedHash = (Get-FileHash $payload.FullName -Algorithm SHA256).Hash
}
$app = Start-Process $exe -PassThru
$deadline = (Get-Date).AddMinutes(3)
$button = $null
$names = if ($probe) { @('Check for updates','업데이트 확인','アップデートを確認') } else { @('Install update','업데이트 설치','アップデートをインストール') }
$seen = @()
do {
  Start-Sleep -Seconds 2
  $app.Refresh()
  if ($app.HasExited) { throw "Public app exited before offering an update: $($app.ExitCode)" }
  if ($app.MainWindowHandle -eq 0) { continue }
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
  if (-not $root) { continue }
  $elements = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $seen = @()
  foreach ($element in $elements) {
    try {
      $name = $element.Current.Name
      if ($name) { $seen += $name }
      if ($element.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and $name -in $names -and $element.Current.IsEnabled) {
        $button = $element; break
      }
    } catch [System.Windows.Automation.ElementNotAvailableException] { continue }
  }
} while (-not $button -and (Get-Date) -lt $deadline)
if (-not $button) { Write-Host "Visible accessibility names: $($seen -join ' | ')"; throw "Public app did not present the expected update button (probe=$probe)" }
if ($probe) {
  Write-Host 'Public v0.1.1 update-check button is accessible via UI Automation; no update was started.'
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  exit 0
}
Write-Host 'Public application displayed an available update without any test instrumentation.'
$pattern = $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
$pattern.Invoke()
Write-Host 'Invoked the actual Install update button via UI Automation.'
$deadline = (Get-Date).AddMinutes(4)
$updated = $false
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 3
  try {
    if ((Test-Path $exe) -and (Get-FileHash $exe -Algorithm SHA256).Hash -eq $expectedHash) {
      $version = (Get-Item $exe).VersionInfo.FileVersion
      if ($version -match ('^' + [regex]::Escape($target) + '(\.0)?$')) { $updated = $true; break }
    }
  } catch { # Installer may temporarily lock or replace the executable.
  }
}
if (-not $updated) { throw "Public update did not install the exact $target MSI payload" }
Write-Host "Public update installed $target; executable SHA-256 matches the public MSI payload."
$relaunch = Start-Process $exe -PassThru
Start-Sleep -Seconds 5
$relaunch.Refresh()
if ($relaunch.HasExited) { throw "Updated app exited immediately: $($relaunch.ExitCode)" }
Stop-Process -Id $relaunch.Id -Force
Write-Host "Updated public $target app relaunched successfully."
