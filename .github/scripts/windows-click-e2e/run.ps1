# Only run on a disposable GitHub-hosted Windows runner: injects mouse and keyboard input.
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:CI -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') { throw 'Requires a disposable GitHub-hosted runner' }
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class TestInput {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
}
'@
$tmp = Join-Path $env:RUNNER_TEMP 'public-auto-clicker-click-test'
New-Item -ItemType Directory -Force $tmp | Out-Null
$msi = Join-Path $tmp 'public.msi'
Invoke-WebRequest 'https://github.com/uulab-official/auto-clicker/releases/download/v0.1.3/Auto.Clicker_0.1.3_x64_en-US.msi' -OutFile $msi
$install = Start-Process msiexec.exe -ArgumentList '/i',"`"$msi`"",'/qn','/norestart' -Wait -PassThru
if ($install.ExitCode -ne 0) { throw "Public MSI install failed: $($install.ExitCode)" }
$exe = Join-Path $env:ProgramFiles 'Auto Clicker\auto-clicker.exe'
if ((Get-Item $exe).VersionInfo.FileVersion -notmatch '^0\.1\.3(\.0)?$') { throw 'Installed application is not v0.1.3' }
$target = Join-Path $tmp 'target.ps1'
$log = Join-Path $tmp 'clicks.txt'
@'
param([string]$Log)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Isolated click target'
$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point(20, 20)
$form.Size = New-Object System.Drawing.Size(250, 200)
$form.TopMost = $true
$form.Add_MouseDown({ param($sender,$event) Add-Content -LiteralPath $Log -Value "$($event.Button),$($event.X),$($event.Y)" })
[System.Windows.Forms.Application]::Run($form)
'@ | Set-Content -LiteralPath $target -Encoding UTF8
$targetProcess = Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$target`"", "`"$log`"" -PassThru
$app = $null
try {
  $app = Start-Process $exe -PassThru
  $deadline = (Get-Date).AddSeconds(90)
  $start = $null
  do {
    Start-Sleep -Seconds 1
    $app.Refresh()
    if ($app.HasExited) { throw 'Public application exited unexpectedly' }
    if ($app.MainWindowHandle -eq 0) { continue }
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
    if (-not $root) { continue }
    $elements = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($e in $elements) {
      try {
        if ($e.Current.Name -eq 'Start clicking' -and $e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and $e.Current.IsEnabled) { $start = $e; break }
      } catch [System.Windows.Automation.ElementNotAvailableException] { continue }
    }
  } while (-not $start -and (Get-Date) -lt $deadline)
  if (-not $start) { throw 'Enabled Start clicking button was not found' }
  # Invoke through UI Automation; place the cursor in the target after invocation
  # before the first click, then verify actual delivered Windows mouse events.
  [TestInput]::SetCursorPos(100,100) | Out-Null
  $start.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
  $deadline = (Get-Date).AddSeconds(20)
  do {
    Start-Sleep -Milliseconds 500
    $count = if (Test-Path $log) { @(Get-Content $log).Count } else { 0 }
  } while ($count -lt 2 -and (Get-Date) -lt $deadline)
  if ($count -lt 2) { throw "Expected at least two delivered clicks, received $count" }
  Write-Host "Public v0.1.3 delivered $count simple clicks to a separate Windows application"
  # Ctrl+Shift+F8, using virtual events confined to the disposable runner.
  foreach ($key in @(0x11,0x10,0x77)) { [TestInput]::keybd_event($key,0,0,[UIntPtr]::Zero) }
  foreach ($key in @(0x77,0x10,0x11)) { [TestInput]::keybd_event($key,0,2,[UIntPtr]::Zero) }
  Start-Sleep -Seconds 2
  $stopped = @(Get-Content $log).Count
  Start-Sleep -Seconds 3
  $after = @(Get-Content $log).Count
  if ($stopped -ne $after) { throw "Clicks continued after emergency stop: $stopped to $after" }
  Write-Host "Global Ctrl+Shift+F8 stopped actual input; count remained $after"
} finally {
  if ($app) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue }
  Stop-Process -Id $targetProcess.Id -Force -ErrorAction SilentlyContinue
}
