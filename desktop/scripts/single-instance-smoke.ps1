param([string]$ExePath = "$PSScriptRoot/../src-tauri/target/debug/edithub-desktop.exe")
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $ExePath).Path
$qa = [IO.Path]::GetFullPath("$PSScriptRoot/../.qa")
if (Get-Process edithub-desktop -ErrorAction SilentlyContinue) { throw 'Close running EditHub instances before this test' }
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class InstanceWindowTest {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int mode);
}
'@
$started = [Collections.Generic.List[Diagnostics.Process]]::new()
$savedConfig = $env:EDITHUB_CONFIG_DIR
$savedProfile = $env:WEBVIEW2_USER_DATA_FOLDER
try {
  $env:EDITHUB_CONFIG_DIR = "$qa/config"
  $env:WEBVIEW2_USER_DATA_FOLDER = "$qa/single-instance-webview"
  $first = Start-Process -FilePath $exe -WindowStyle Hidden -PassThru
  $started.Add($first)
  $deadline = [DateTime]::UtcNow.AddSeconds(20)
  do {
    Start-Sleep -Milliseconds 100
    $first.Refresh()
    $hwnd = $first.MainWindowHandle
  } while ($hwnd -eq [IntPtr]::Zero -and !$first.HasExited -and [DateTime]::UtcNow -lt $deadline)
  if ($hwnd -eq [IntPtr]::Zero) { throw 'First instance did not create a window' }
  function Invoke-AnotherLaunch {
    $next = Start-Process -FilePath $exe -WindowStyle Hidden -PassThru
    $started.Add($next)
    if (!$next.WaitForExit(5000)) { throw 'Second launch remained running: duplicate app instance' }
    if ($next.ExitCode -ne 0) { throw "Second launch failed: $($next.ExitCode)" }
    Start-Sleep -Milliseconds 250
    if ($first.HasExited) { throw 'Original instance exited' }
    if (@(Get-Process edithub-desktop -ErrorAction SilentlyContinue).Count -ne 1) { throw 'Expected exactly one app process' }
    if (![InstanceWindowTest]::IsWindowVisible($hwnd) -or [InstanceWindowTest]::IsIconic($hwnd)) { throw 'Original window was not restored' }
  }
  1..3 | ForEach-Object { Invoke-AnotherLaunch }
  [InstanceWindowTest]::ShowWindow($hwnd, 6) | Out-Null
  if (![InstanceWindowTest]::IsIconic($hwnd)) { throw 'Could not minimize test window' }
  Invoke-AnotherLaunch
  [InstanceWindowTest]::PostMessage($hwnd, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
  Start-Sleep -Milliseconds 350
  if ([InstanceWindowTest]::IsWindowVisible($hwnd)) { throw 'Close did not hide the app in tray' }
  Invoke-AnotherLaunch
  Write-Output 'PASS: repeated launches exit, original process survives, minimized and tray windows restore'
} finally {
  foreach ($process in $started) { if (!$process.HasExited) { Stop-Process -Id $process.Id -ErrorAction SilentlyContinue } }
  $env:EDITHUB_CONFIG_DIR = $savedConfig
  $env:WEBVIEW2_USER_DATA_FOLDER = $savedProfile
}
