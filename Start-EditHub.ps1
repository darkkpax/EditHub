$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$WindowsDir = Join-Path $Root 'windows'
$ServerDir = Join-Path $Root 'server'
$ElectronDir = $WindowsDir
$NodeDir = Join-Path $Root 'tools\node20'
$NodeExe = Join-Path $NodeDir 'node.exe'
$Npm = Join-Path $NodeDir 'npm.cmd'
$Npx = Join-Path $NodeDir 'npx.cmd'
$ServerLog = Join-Path $ServerDir 'server.log'
$ServerErrorLog = Join-Path $ServerDir 'server.err.log'
$ViteLog = Join-Path $WindowsDir 'vite.log'
$ViteErrorLog = Join-Path $WindowsDir 'vite.err.log'
$LauncherLog = Join-Path $Root 'Start-EditHub.log'

function Write-LauncherLog {
  param([string] $Message)

  $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
  Add-Content -LiteralPath $LauncherLog -Value $line
  Write-Host $Message
}

function Stop-LauncherOnError {
  param([string] $Message)

  Write-Host ''
  Write-Host $Message -ForegroundColor Red
  Write-Host "Лог: $LauncherLog" -ForegroundColor Yellow
  Write-Host "Vite log: $ViteLog" -ForegroundColor Yellow
  Write-Host "Vite error log: $ViteErrorLog" -ForegroundColor Yellow
  Write-Host "Server log: $ServerLog" -ForegroundColor Yellow
  Write-Host "Server error log: $ServerErrorLog" -ForegroundColor Yellow
  Read-Host 'Нажми Enter чтобы закрыть'
  exit 1
}

if (Test-Path $NodeDir) {
  $env:PATH = "$NodeDir;$env:PATH"
}

if (-not (Test-Path $Npm)) {
  $Npm = 'npm.cmd'
}

if (-not (Test-Path $Npx)) {
  $Npx = 'npx.cmd'
}

if (-not (Test-Path $NodeExe)) {
  $NodeExe = 'node.exe'
}

function Test-LocalPortOpen {
  param([int] $Port)

  $Client = [System.Net.Sockets.TcpClient]::new()
  try {
    $Connection = $Client.BeginConnect('127.0.0.1', $Port, $null, $null)
    if (-not $Connection.AsyncWaitHandle.WaitOne(300, $false)) {
      return $false
    }

    $Client.EndConnect($Connection)
    return $true
  } catch {
    return $false
  } finally {
    $Client.Close()
  }
}

$env:ELECTRON_RUN_AS_NODE = ''
$env:EDITHUB_DISABLE_DROPFX = '1'
$env:JWT_SECRET = 'local-edithub-dev-secret-please-change-32chars'
$env:HOST = '127.0.0.1'
$env:PORT = '3000'

try {
  Set-Content -LiteralPath $LauncherLog -Value ("[{0}] Launcher started" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

  Write-LauncherLog 'Stopping old EditHub processes...'
  Get-Process electron -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" |
    Where-Object {
      $_.CommandLine -and (
        $_.CommandLine -match 'vite\.js' -or
        $_.CommandLine -match 'dev:vite' -or
        $_.CommandLine -match 'npm-cli\.js.*run dev:vite'
      )
    } |
    ForEach-Object {
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

  if ((Test-Path $ServerDir) -and -not (Test-LocalPortOpen -Port 3000)) {
    Write-LauncherLog 'Starting EditHub server...'
    Start-Process -FilePath $NodeExe `
      -ArgumentList 'src/index.js' `
      -WorkingDirectory $ServerDir `
      -RedirectStandardOutput $ServerLog `
      -RedirectStandardError $ServerErrorLog `
      -WindowStyle Hidden
  } elseif (Test-LocalPortOpen -Port 3000) {
    Write-LauncherLog 'EditHub server is already running on 127.0.0.1:3000.'
  }

  if (-not (Test-LocalPortOpen -Port 5173)) {
    Write-LauncherLog 'Starting Vite dev server...'
    Start-Process -FilePath $Npm `
      -ArgumentList 'run', 'dev:vite' `
      -WorkingDirectory $WindowsDir `
      -RedirectStandardOutput $ViteLog `
      -RedirectStandardError $ViteErrorLog `
      -WindowStyle Hidden
  } else {
    Write-LauncherLog 'Vite is already running on 127.0.0.1:5173.'
  }

  $ViteReady = $false
  for ($i = 0; $i -lt 60; $i++) {
    if (Test-LocalPortOpen -Port 5173) {
      $ViteReady = $true
      break
    }
    Start-Sleep -Milliseconds 500
  }

  if (-not $ViteReady) {
    throw 'Vite did not start on 127.0.0.1:5173.'
  }

  Write-LauncherLog 'Starting EditHub without DropFX...'
  Push-Location $WindowsDir
  try {
    & $Npm run dev:electron 2>&1 | Tee-Object -FilePath $LauncherLog -Append
    if ($LASTEXITCODE -ne 0) {
      throw "Electron launcher exited with code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }
} catch {
  Stop-LauncherOnError $_.Exception.Message
}
