# UI automation is restricted to disposable GitHub-hosted Windows VMs.
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:CI -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') { throw 'Requires a disposable GitHub-hosted runner' }
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
$work = Join-Path $env:RUNNER_TEMP 'auto-clicker-profile-e2e'
New-Item -ItemType Directory -Force $work | Out-Null
$exe = Join-Path $env:GITHUB_WORKSPACE 'src-tauri\target\release\auto-clicker.exe'
$invalid = Join-Path $work 'invalid.json'
Set-Content -LiteralPath $invalid -Encoding UTF8 -Value '{"format":"auto-clicker-settings","version":99,"settings":{}}'
$app = Start-Process $exe -PassThru

function Find-AppNode([scriptblock]$test, [int]$seconds = 30) {
  $deadline = (Get-Date).AddSeconds($seconds)
  do {
    $app.Refresh()
    if ($app.HasExited) { throw 'App exited unexpectedly' }
    if ($app.MainWindowHandle -ne 0) {
      try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
        $nodes = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($node in $nodes) { try { if (& $test $node) { return $node } } catch { } }
      } catch { }
    }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  throw 'Requested app control did not appear'
}
function Invoke-AppButton([string]$name) {
  $deadline = (Get-Date).AddSeconds(30)
  do {
    try {
      $button = Find-AppNode { param($n) $n.Current.Name -eq $name -and $n.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and $n.Current.IsEnabled } 2
      $pattern = $null
      if ($button.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) { $pattern.Invoke(); Write-Host "Invoked app control: $name"; return }
    } catch { }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  throw "Cannot invoke app button '$name'"
}
function Set-Delay([int]$seconds) {
  $deadline = (Get-Date).AddSeconds(20)
  do {
    try {
      $field = Find-AppNode { param($n) $n.Current.Name -like '*Start delay*' -and $n.Current.ControlType -eq [System.Windows.Automation.ControlType]::Spinner } 2
      $field.SetFocus()
      [System.Windows.Forms.SendKeys]::SendWait('^a')
      [System.Windows.Forms.SendKeys]::SendWait([string]$seconds)
      [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
      Write-Host "Set start delay to $seconds seconds"
      return
    } catch { Start-Sleep -Milliseconds 250 }
  } while ((Get-Date) -lt $deadline)
  throw 'Start delay spinner cannot be edited through UI Automation'
}
function Wait-Dialog([string]$title) {
  $deadline = (Get-Date).AddSeconds(30)
  do {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($window in $windows) {
      try { if ($window.Current.Name -eq $title -and $window.Current.ProcessId -eq $app.Id) { return $window } } catch { }
    }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  Write-Host "Native dialog '$title' not found; desktop window diagnostics:"
  $windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
  foreach ($window in $windows) { try { Write-Host "Window pid=$($window.Current.ProcessId) name=$($window.Current.Name) class=$($window.Current.ClassName)" } catch { } }
  try {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
    $nodes = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    Write-Host 'Current app UI labels:'
    foreach ($node in $nodes) { try { if ($node.Current.Name) { Write-Host "$($node.Current.ControlType.ProgrammaticName): $($node.Current.Name)" } } catch { } }
  } catch { Write-Host "App UI diagnostic failed: $_" }
  throw "Native dialog '$title' did not appear for app PID $($app.Id)"
}
function Choose-File([string]$title, [string]$path, [string]$buttonName) {
  $dialog = Wait-Dialog $title
  $nodes = $dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $fileName = $null; $confirm = $null
  foreach ($node in $nodes) {
    try {
      $c = $node.Current
      if ($c.ControlType -eq [System.Windows.Automation.ControlType]::Edit -and ($c.AutomationId -eq '1001' -or $c.Name -match '^File name:?$')) { $fileName = $node }
      if ($c.ControlType -eq [System.Windows.Automation.ControlType]::Button -and $c.Name -eq $buttonName -and $c.IsEnabled) { $confirm = $node }
    } catch { }
  }
  if (-not $fileName -or -not $confirm) { throw "Cannot locate filename input or $buttonName button in $title" }
  $fileName.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($path)
  $confirm.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}
function Cancel-Dialog([string]$title) {
  $dialog = Wait-Dialog $title
  $buttons = $dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  foreach ($button in $buttons) {
    try { if ($button.Current.Name -eq 'Cancel' -and $button.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button) { $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return } } catch { }
  }
  throw "Cannot find Cancel in $title"
}
function Wait-Text([string]$text) { $null = Find-AppNode { param($n) $n.Current.Name -like "*$text*" } }
function Export-Settings([string]$path) {
  Invoke-AppButton 'Export settings'
  Choose-File 'Export settings' $path 'Save'
  Wait-Text 'Settings exported.'
  if (-not (Test-Path -LiteralPath $path)) { throw "Export did not create $path" }
  $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  if ($data.format -ne 'auto-clicker-settings' -or $data.version -ne 1) { throw 'Unexpected backup format' }
  return $data.settings
}
function Import-Settings([string]$path) {
  Invoke-AppButton 'Import settings'
  Choose-File 'Import settings' $path 'Open'
}

try {
  Set-Delay 3
  $original = Join-Path $work 'original.json'
  if ((Export-Settings $original).startDelayMs -ne 3000) { throw 'Original settings export did not include the 3s delay' }
  Set-Delay 7
  if ((Export-Settings (Join-Path $work 'changed.json')).startDelayMs -ne 7000) { throw 'Modified setting was not exported' }
  Import-Settings $original
  Wait-Text 'Settings imported.'
  if ((Export-Settings (Join-Path $work 'restored.json')).startDelayMs -ne 3000) { throw 'Import did not restore the original setting' }
  Import-Settings $invalid
  Wait-Text 'Could not import settings.'
  if ((Export-Settings (Join-Path $work 'after-invalid.json')).startDelayMs -ne 3000) { throw 'Invalid import modified settings' }
  Invoke-AppButton 'Import settings'
  Cancel-Dialog 'Import settings'
  if ((Export-Settings (Join-Path $work 'after-cancel.json')).startDelayMs -ne 3000) { throw 'Cancelled import modified settings' }
  Write-Host 'Verified native Windows export, restoration, invalid-file preservation, and import cancellation'
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
}
