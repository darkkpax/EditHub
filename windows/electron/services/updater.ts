import { app, BrowserWindow } from 'electron'
import { logLine } from '../logger'

let autoUpdaterRef: typeof import('electron-updater').autoUpdater | null = null

export function installDownloadedUpdate(): void {
  autoUpdaterRef?.quitAndInstall()
}

/**
 * Auto-update via electron-updater + GitHub Releases.
 *
 * Flow: the GitHub Action builds an NSIS installer and a `latest.yml`
 * manifest and publishes them to a GitHub Release. On launch the packaged
 * app reads `latest.yml`, and if a newer version exists it downloads the
 * installer in the background and installs it the next time the app quits.
 *
 * Disabled in dev (electron-updater requires a packaged app).
 */
export function setupAutoUpdate(mainWindow: BrowserWindow | null): void {
  if (!app.isPackaged) {
    logLine('INFO', 'autoUpdate skipped (not packaged)')
    return
  }

  // Imported lazily so a dev run without the dependency installed still boots.
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { autoUpdater } = require('electron-updater') as typeof import('electron-updater')
  autoUpdaterRef = autoUpdater

  autoUpdater.autoDownload = true
  autoUpdater.autoInstallOnAppQuit = true

  const send = (channel: string, payload?: unknown) => {
    mainWindow?.webContents.send(channel, payload)
  }

  autoUpdater.on('checking-for-update', () => logLine('INFO', 'update:checking'))
  autoUpdater.on('update-available', (info) => {
    logLine('INFO', 'update:available', { version: info.version })
    send('update:available', { version: info.version })
  })
  autoUpdater.on('update-not-available', () => logLine('INFO', 'update:none'))
  autoUpdater.on('download-progress', (p) => {
    send('update:progress', { percent: Math.round(p.percent) })
  })
  autoUpdater.on('update-downloaded', (info) => {
    logLine('INFO', 'update:downloaded', { version: info.version })
    send('update:downloaded', { version: info.version })
  })
  autoUpdater.on('error', (err) => {
    logLine('ERROR', 'update:error', err?.message || err)
  })

  autoUpdater.checkForUpdates().catch((err) => {
    logLine('WARN', 'update:checkFailed', err?.message || err)
  })

  // Re-check hourly so a long-running edit session still gets a prompt.
  setInterval(() => {
    autoUpdater.checkForUpdates().catch(() => {})
  }, 60 * 60 * 1000)
}
