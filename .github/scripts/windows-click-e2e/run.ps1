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
  [StructLayout(LayoutKind.Sequential)] public struct Point { public int X; public int Y; }
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out Rect rect);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point point);
  [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
}
'@
$tmp = Join-Path $env:RUNNER_TEMP 'public-auto-clicker-click-test'
New-Item -ItemType Directory -Force $tmp | Out-Null
$exe = $env:AUTOCLICKER_TEST_EXE
if (-not $exe) {
  $msi = Join-Path $tmp 'public.msi'
  Invoke-WebRequest 'https://github.com/uulab-official/auto-clicker/releases/download/v0.1.3/Auto.Clicker_0.1.3_x64_en-US.msi' -OutFile $msi
  $install = Start-Process msiexec.exe -ArgumentList '/i',"`"$msi`"",'/qn','/norestart' -Wait -PassThru
  if ($install.ExitCode -ne 0) { throw "Public MSI install failed: $($install.ExitCode)" }
  $exe = Join-Path $env:ProgramFiles 'Auto Clicker\auto-clicker.exe'
  if ((Get-Item $exe).VersionInfo.FileVersion -notmatch '^0\.1\.3(\.0)?$') { throw 'Installed application is not v0.1.3' }
}
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
$targetOut = Join-Path $tmp 'target.stdout'
$targetErr = Join-Path $tmp 'target.stderr'
$targetProcess = Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$target`"", "`"$log`"" -RedirectStandardOutput $targetOut -RedirectStandardError $targetErr -PassThru
$app = $null
function Find-Buttons([string]$name) {
  $window = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
  $nodes = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  foreach ($node in $nodes) {
    try {
      if ($node.Current.Name -eq $name -and $node.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and $node.Current.IsEnabled) { $node }
    } catch [System.Windows.Automation.ElementNotAvailableException] { continue }
  }
}
function Invoke-Button([string]$name, [int]$index = 0) {
  $deadline = (Get-Date).AddSeconds(10)
  do {
    try {
      $buttons = @(Find-Buttons $name)
      if ($buttons.Count -gt $index) {
        $button = $buttons[$index]
        $pattern = $null
        if ($button.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) { $pattern.Invoke(); return }
        if ($button.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$pattern)) { $pattern.Toggle(); return }
      }
    } catch { }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  throw "Enabled button '$name' index $index could not be invoked"
}
function Wait-AppText([string]$text) {
  $deadline = (Get-Date).AddSeconds(20)
  do {
    try {
      $window = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
      $nodes = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
      foreach ($node in $nodes) {
        try { if ($node.Current.Name -like "*$text*") { Write-Host "Observed app text: $text"; return } } catch { }
      }
    } catch { }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  throw "App did not show expected text: $text"
}
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
  $deadline = (Get-Date).AddSeconds(15)
  do {
    $targetProcess.Refresh()
    if ($targetProcess.HasExited) { throw "Target exited before test: $(Get-Content $targetErr -Raw)" }
    if ($targetProcess.MainWindowHandle -ne 0) { break }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  if ($targetProcess.MainWindowHandle -eq 0) { throw 'Target window handle unavailable' }
  $rect = [TestInput+Rect]::new()
  if (-not [TestInput]::GetWindowRect($targetProcess.MainWindowHandle,[ref]$rect)) { throw 'Cannot get target window rectangle' }
  Write-Host "Target handle=$($targetProcess.MainWindowHandle) rectangle=$($rect.Left),$($rect.Top)-$($rect.Right),$($rect.Bottom)"
  # Invoke through UI Automation; place the cursor in the target after invocation
  # before the first click, then verify actual delivered Windows mouse events.
  $x = $rect.Left + 100; $y = $rect.Top + 100
  [TestInput]::SetCursorPos($x,$y) | Out-Null
  $point = [TestInput+Point]::new()
  [TestInput]::GetCursorPos([ref]$point) | Out-Null
  $under = [TestInput]::WindowFromPoint($point)
  Write-Host "Cursor=$($point.X),$($point.Y); window under pointer=$under"
  if ($under -ne $targetProcess.MainWindowHandle) { throw 'Target window is not under the pointer' }
  Invoke-Button 'Start clicking'
  $deadline = (Get-Date).AddSeconds(20)
  do {
    Start-Sleep -Milliseconds 500
    $count = if (Test-Path $log) { @(Get-Content $log).Count } else { 0 }
  } while ($count -lt 2 -and (Get-Date) -lt $deadline)
  if ($count -lt 2) {
    Write-Host "Target stderr: $(Get-Content $targetErr -Raw)"
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
    $elements = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    $names = foreach ($e in $elements) { try { if ($e.Current.Name) { $e.Current.Name } } catch {} }
    Write-Host "App UI names after start: $($names -join ' | ')"
    [TestInput]::GetCursorPos([ref]$point) | Out-Null
    Write-Host "Cursor after start=$($point.X),$($point.Y); window under pointer=$([TestInput]::WindowFromPoint($point))"
    throw "Expected at least two delivered clicks, received $count"
  }
  Write-Host "Tested application delivered $count simple clicks to a separate Windows application"
  # Ctrl+Shift+F8, using virtual events confined to the disposable runner.
  foreach ($key in @(0x11,0x10,0x77)) { [TestInput]::keybd_event($key,0,0,[UIntPtr]::Zero) }
  foreach ($key in @(0x77,0x10,0x11)) { [TestInput]::keybd_event($key,0,2,[UIntPtr]::Zero) }
  Start-Sleep -Seconds 2
  $stopped = @(Get-Content $log).Count
  Start-Sleep -Seconds 3
  $after = @(Get-Content $log).Count
  if ($stopped -ne $after) { throw "Clicks continued after emergency stop: $stopped to $after" }
  Write-Host "Global Ctrl+Shift+F8 stopped actual input; count remained $after"

  # Configure two positions in the public UI and check two complete cycles in
  # the target's mouse event log. All input remains inside this disposable VM.
  Invoke-Button 'Sequence'
  # UIA Invoke may return before the WebView handles the tab click. Wait for
  # the sequence view, otherwise the next action can capture the simple step.
  Wait-AppText 'Actions run from top to bottom, then repeat.'
  Invoke-Button 'Pick position'
  [TestInput]::SetCursorPos(($rect.Left + 70),($rect.Top + 100)) | Out-Null
  Wait-AppText "Position captured: $(($rect.Left + 70)), $(($rect.Top + 100))."
  Invoke-Button '+ Add click'
  Invoke-Button 'Pick position' 1
  [TestInput]::SetCursorPos(($rect.Left + 160),($rect.Top + 100)) | Out-Null
  Wait-AppText "Position captured: $(($rect.Left + 160)), $(($rect.Top + 100))."
  Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
  Invoke-Button 'Start clicking'
  $deadline = (Get-Date).AddSeconds(25)
  do {
    Start-Sleep -Milliseconds 500
    $lines = if (Test-Path $log) { @(Get-Content $log) } else { @() }
  } while ($lines.Count -lt 4 -and (Get-Date) -lt $deadline)
  foreach ($key in @(0x11,0x10,0x77)) { [TestInput]::keybd_event($key,0,0,[UIntPtr]::Zero) }
  foreach ($key in @(0x77,0x10,0x11)) { [TestInput]::keybd_event($key,0,2,[UIntPtr]::Zero) }
  if ($lines.Count -lt 4) { throw "Expected four sequence clicks, received $($lines.Count): $($lines -join '; ')" }
  $xs = @($lines[0..3] | ForEach-Object { [int](($_ -split ',')[1]) })
  if ([Math]::Abs($xs[0] - $xs[2]) -gt 2 -or [Math]::Abs($xs[1] - $xs[3]) -gt 2 -or ($xs[1] - $xs[0]) -lt 70) {
    throw "Sequence positions did not repeat in order: $($lines[0..3] -join '; ')"
  }
  Write-Host "Two configured positions delivered in order over two cycles: $($lines[0..3] -join '; ')"

  # Configure a finite run from the real UI: two right-button double clicks.
  # The independent target must receive exactly four right-button down events.
  Start-Sleep -Seconds 2
  Invoke-Button 'Simple click'
  function Find-Control([System.Windows.Automation.ControlType]$type, [string]$name) {
    $window = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
    $nodes = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($node in $nodes) {
      try { if ($node.Current.ControlType -eq $type -and $node.Current.Name -eq $name) { return $node } } catch { }
    }
    throw "UI control '$name' ($($type.ProgrammaticName)) unavailable"
  }
  function Select-Option([string]$label, [string]$option) {
    $combo = Find-Control ([System.Windows.Automation.ControlType]::ComboBox) $label
    $combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
    Start-Sleep -Milliseconds 500
    $item = Find-Control ([System.Windows.Automation.ControlType]::ListItem) $option
    $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
  }
  Select-Option 'Mouse button' 'Right'
  Select-Option 'Click type' 'Double click'
  $window = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
  $nodes = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $radios = @($nodes | Where-Object { $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::RadioButton })
  if ($radios.Count -ne 2) { throw "Expected two repetition radio buttons, found $($radios.Count)" }
  $radios[1].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
  $repetitions = Find-Control ([System.Windows.Automation.ControlType]::Spinner) 'Number of repetitions'
  $range = $null
  if ($repetitions.TryGetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern, [ref]$range)) {
    $range.SetValue(2)
  } else {
    $repetitions.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('2')
  }
  Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
  [TestInput]::SetCursorPos(($rect.Left + 100),($rect.Top + 100)) | Out-Null
  Invoke-Button 'Start clicking'
  $deadline = (Get-Date).AddSeconds(20)
  do {
    Start-Sleep -Milliseconds 500
    $lines = if (Test-Path $log) { @(Get-Content $log) } else { @() }
  } while ($lines.Count -lt 4 -and (Get-Date) -lt $deadline)
  Start-Sleep -Seconds 4
  $lines = if (Test-Path $log) { @(Get-Content $log) } else { @() }
  if ($lines.Count -ne 4 -or @($lines | Where-Object { $_ -notmatch '^Right,' }).Count -ne 0) {
    throw "Expected exactly four right-button events from two double-click cycles: $($lines -join '; ')"
  }
  Write-Host "Finite two-cycle right double-click run delivered exactly four right events and stopped: $($lines -join '; ')"
} finally {
  if ($app) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue }
  Stop-Process -Id $targetProcess.Id -Force -ErrorAction SilentlyContinue
}
