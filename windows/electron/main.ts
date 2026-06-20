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
import { FileWatcher } from './services/watcher'
import { ICloudSync } from './services/icloud'
import { Archiver } from './services/archiver'
import { DropFXBackend } from './dropfx-backend'
import { loadSettings } from './services/settings-store'

let mainWindow: BrowserWindow | null = null
let tray: Tray | null = null
let fileWatcher: FileWatcher | null = null
let icloudSync: ICloudSync | null = null
let archiver: Archiver | null = null
let dropfxBackend: DropFXBackend | null = null

const isDev = process.env.NODE_ENV === 'development' || !app.isPackaged

function createTrayIcon(): ReturnType<typeof nativeImage.createEmpty> {
  // Simple circle SVG encoded as base64 PNG via data URL
  const svgContent = `<svg width="16" height="16" xmlns="http://www.w3.org/2000/svg">
    <circle cx="8" cy="8" r="7" fill="#6d6df0" stroke="#ffffff" stroke-width="1"/>
    <text x="8" y="12" text-anchor="middle" fill="white" font-size="9" font-family="Arial" font-weight="bold">E</text>
  </svg>`
  // Use a simple colored rectangle as fallback since we can't easily convert SVG to PNG in pure Node
  return nativeImage.createEmpty()
}

function createWindow(): void {
  const settings = loadSettings()

  mainWindow = new BrowserWindow({
    width: 900,
    height: 600,
    minWidth: 720,
    minHeight: 480,
    frame: false,
    transparent: false,
    backgroundColor: '#1c1c1e',
    titleBarStyle: 'hidden',
    resizable: true,
    show: false,
    icon: path.join(__dirname, '../../assets/icon.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  })

  if (isDev) {
    mainWindow.loadURL('http://localhost:5173')
    mainWindow.webContents.openDevTools({ mode: 'detach' })
  } else {
    mainWindow.loadFile(path.join(__dirname, '../renderer/index.html'))
  }

  mainWindow.once('ready-to-show', () => {
    mainWindow?.show()
  })

  mainWindow.on('close', (e) => {
    // Minimize to tray instead of closing
    e.preventDefault()
    mainWindow?.hide()
  })

  mainWindow.on('closed', () => {
    mainWindow = null
  })
}

function createTray(): void {
  // Try to load icon file, fall back to empty image
  const iconPath = path.join(__dirname, '../../assets/tray-icon.png')
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
    const contextMenu = Menu.buildFromTemplate([
      {
        label: 'Show EditHub',
        click: () => {
          mainWindow?.show()
          mainWindow?.focus()
        },
      },
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
    ])
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

function setupServices(): void {
  const settings = loadSettings()

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

  // Start DropFX backend
  dropfxBackend = new DropFXBackend()
  dropfxBackend.start().catch((err) => {
    console.warn('DropFX backend failed to start:', err.message)
  })
}

app.whenReady().then(() => {
  createWindow()
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
})

app.on('window-all-closed', () => {
  // On Windows, keep app running in tray
  if (process.platform !== 'darwin') {
    // Don't quit — stay in tray
  }
})

app.on('before-quit', () => {
  // Allow actual quit
  mainWindow?.removeAllListeners('close')
  fileWatcher?.stop()
  icloudSync?.stop()
  archiver?.stop()
  dropfxBackend?.stop()
})

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow()
  }
})

export { mainWindow }
