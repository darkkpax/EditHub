import {
  app,
  BrowserWindow,
  Tray,
  Menu,
  nativeImage,
  ipcMain,
} from 'electron'
import * as path from 'path'
import * as fs from 'fs'
import { setupProjectsIPC } from './ipc/projects'
import { setupSettingsIPC } from './ipc/settings'
import { setupShellIPC } from './ipc/shell'
import { sweepExtractingDirs } from './services/project-store'
import { setupAutoUpdate } from './services/updater'
import { FileWatcher } from './services/watcher'
import { ICloudSync } from './services/icloud'
import { Archiver } from './services/archiver'
import { DropFXBackend } from './dropfx-backend'
import { loadSettings } from './services/settings-store'
import { isDropFXDisabled } from './runtime-flags'
import { getLogPath, logLine } from './logger'

let mainWindow: BrowserWindow | null = null
let dropfxWindow: BrowserWindow | null = null
let tray: Tray | null = null
let fileWatcher: FileWatcher | null = null
let icloudSync: ICloudSync | null = null
let archiver: Archiver | null = null
let dropfxBackend: DropFXBackend | null = null

const isDev = process.env.NODE_ENV === 'development' || !app.isPackaged
const dropfxDisabled = isDropFXDisabled()

process.on('uncaughtException', (err) => {
  logLine('ERROR', 'uncaughtException', err)
})

process.on('unhandledRejection', (reason) => {
  logLine('ERROR', 'unhandledRejection', reason)
})

function createTrayIcon(): ReturnType<typeof nativeImage.createEmpty> {
  // Simple circle SVG encoded as base64 PNG via data URL
  const svgContent = `<svg width="16" height="16" xmlns="http://www.w3.org/2000/svg">
    <circle cx="8" cy="8" r="7" fill="#6d6df0" stroke="#ffffff" stroke-width="1"/>
    <text x="8" y="12" text-anchor="middle" fill="white" font-size="9" font-family="Arial" font-weight="bold">E</text>
  </svg>`
  // Use a simple colored rectangle as fallback since we can't easily convert SVG to PNG in pure Node
  return nativeImage.createEmpty()
}

function loadRenderer(window: BrowserWindow, appName: 'edithub' | 'dropfx'): void {
  if (isDev) {
    const suffix = appName === 'dropfx' ? '?app=dropfx' : ''
    window.loadURL(`http://127.0.0.1:5173/${suffix}`)
  } else {
    window.loadFile(path.join(__dirname, '../renderer/index.html'), {
      query: appName === 'dropfx' ? { app: 'dropfx' } : {},
    })
  }
}

function createAppWindow(options: {
  title: string
  width: number
  height: number
  minWidth: number
  minHeight: number
  appName: 'edithub' | 'dropfx'
}): BrowserWindow {
  const iconName = options.appName === 'dropfx' ? 'dropfx-icon.png' : 'edithub-icon.png'
  logLine('INFO', 'createWindow', { title: options.title, appName: options.appName, logPath: getLogPath() })
  const window = new BrowserWindow({
    width: options.width,
    height: options.height,
    minWidth: options.minWidth,
    minHeight: options.minHeight,
    frame: false,
    transparent: false,
    backgroundColor: '#1c1c1e',
    titleBarStyle: 'hidden',
    title: options.title,
    resizable: true,
    show: false,
    icon: path.join(__dirname, '../../assets', iconName),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  })

  loadRenderer(window, options.appName)

  window.once('ready-to-show', () => {
    logLine('INFO', 'ready-to-show', options.title)
    window.show()
  })

  window.webContents.on('did-start-loading', () => {
    logLine('INFO', 'did-start-loading', options.title)
  })

  window.webContents.on('dom-ready', () => {
    logLine('INFO', 'dom-ready', options.title)
  })

  window.webContents.on('did-finish-load', () => {
    logLine('INFO', 'did-finish-load', options.title)
  })

  window.webContents.on('did-fail-load', (_event, errorCode, errorDescription, validatedURL) => {
    logLine('ERROR', 'did-fail-load', {
      title: options.title,
      errorCode,
      errorDescription,
      validatedURL,
    })
  })

  window.webContents.on('render-process-gone', (_event, details) => {
    logLine('ERROR', 'render-process-gone', { title: options.title, details })
  })

  window.on('close', (e) => {
    // Minimize to tray instead of closing
    e.preventDefault()
    window.hide()
  })

  return window
}

function createWindows(): void {
  mainWindow = createAppWindow({
    title: 'EditHub',
    width: 900,
    height: 600,
    minWidth: 720,
    minHeight: 480,
    appName: 'edithub',
  })

  if (!dropfxDisabled) {
    dropfxWindow = createAppWindow({
      title: 'DropFX',
      width: 920,
      height: 620,
      minWidth: 760,
      minHeight: 480,
      appName: 'dropfx',
    })
  }
}

function createTray(): void {
  // Try to load icon file, fall back to empty image
  const iconPath = path.join(__dirname, '../../assets/edithub-icon-32.png')
  let icon: ReturnType<typeof nativeImage.createFromPath>
  if (fs.existsSync(iconPath)) {
    icon = nativeImage.createFromPath(iconPath)
    if (icon.isEmpty()) {
      icon = createTrayIcon()
    }
  } else {
    icon = createTrayIcon()
  }

  tray = new Tray(icon)
  tray.setToolTip('EditHub')

  const updateContextMenu = (activeProject?: string) => {
    const template: Electron.MenuItemConstructorOptions[] = [
      {
        label: 'Show EditHub',
        click: () => {
          mainWindow?.show()
          mainWindow?.focus()
        },
      },
    ]

    if (!dropfxDisabled) {
      template.push({
        label: 'Show DropFX',
        click: () => {
          dropfxWindow?.show()
          dropfxWindow?.focus()
        },
      })
    }

    template.push(
      {
        label: `Active Project: ${activeProject || 'None'}`,
        enabled: false,
      },
      { type: 'separator' },
      {
        label: 'Quit',
        click: () => {
          app.quit()
        },
      },
    )

    const contextMenu = Menu.buildFromTemplate(template)
    tray?.setContextMenu(contextMenu)
  }

  updateContextMenu()

  tray.on('click', () => {
    if (mainWindow?.isVisible()) {
      mainWindow.hide()
    } else {
      mainWindow?.show()
      mainWindow?.focus()
    }
  })

  // Update tray context menu when active project changes
  ipcMain.on('active:changed', (_e, { projectId }: { projectId: string }) => {
    updateContextMenu(projectId)
  })
}

ipcMain.on('debug:log', (_e, payload: { level: 'INFO' | 'WARN' | 'ERROR'; message: string; details?: unknown }) => {
  logLine(payload.level, `renderer:${payload.message}`, payload.details)
})

function setupServices(): void {
  const settings = loadSettings()

  // Clean up orphaned `__extracting_*` temp folders from interrupted
  // extractions before anything else touches the folders.
  try {
    const sweepTargets = [
      settings.projectsFolder,
      settings.icloudPath ? path.join(settings.icloudPath, 'EditHub', 'Videos') : '',
    ].filter(Boolean)
    const swept = sweepExtractingDirs(sweepTargets)
    logLine('INFO', 'sweepExtractingDirs', swept)
  } catch (err) {
    logLine('WARN', 'sweepExtractingDirs failed', err)
  }

  // Start file watcher
  fileWatcher = new FileWatcher(mainWindow)
  if (settings.projectsFolder && fs.existsSync(settings.projectsFolder)) {
    fileWatcher.watchProjectsFolder(settings.projectsFolder)
  }
  if (settings.downloadsFolder && fs.existsSync(settings.downloadsFolder)) {
    fileWatcher.watchDownloadsFolder(
      settings.downloadsFolder,
      settings.autoImportPatterns || ['*-enhanced*', '*-enhanced-v2*']
    )
  }

  // Start iCloud sync
  icloudSync = new ICloudSync(mainWindow)
  icloudSync.start()

  // Start archiver
  archiver = new Archiver(mainWindow)
  archiver.start(settings.autoArchiveDays ?? 30)

  if (!dropfxDisabled) {
    dropfxBackend = new DropFXBackend()
    dropfxBackend.start().catch((err) => {
      console.warn('DropFX backend failed to start:', err.message)
    })
  }
}

app.whenReady().then(() => {
  logLine('INFO', 'app.whenReady')
  createWindows()
  createTray()
  setupServices()

  // Setup IPC handlers
  setupProjectsIPC(ipcMain, mainWindow, fileWatcher)
  setupSettingsIPC(ipcMain, mainWindow, (settings) => {
    // Re-initialize watchers when settings change
    if (fileWatcher) {
      fileWatcher.updateSettings(settings)
    }
    if (icloudSync) {
      icloudSync.updateSettings(settings)
    }
    if (archiver) {
      archiver.updateAutoArchiveDays(settings.autoArchiveDays ?? 30)
    }
  })
  setupShellIPC(ipcMain)
  logLine('INFO', 'IPC handlers registered')

  // Check GitHub Releases for a newer version and self-update.
  setupAutoUpdate(mainWindow)
})

app.on('window-all-closed', () => {
  // On Windows, keep app running in tray
  if (process.platform !== 'darwin') {
    // Don't quit — stay in tray
  }
})

app.on('before-quit', () => {
  // Allow actual quit
  logLine('INFO', 'before-quit')
  mainWindow?.removeAllListeners('close')
  dropfxWindow?.removeAllListeners('close')
  fileWatcher?.stop()
  icloudSync?.stop()
  archiver?.stop()
  dropfxBackend?.stop()
})

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    logLine('INFO', 'activate -> recreate windows')
    createWindows()
  }
})

export { mainWindow }
