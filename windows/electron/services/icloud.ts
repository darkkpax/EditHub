import * as fs from 'fs'
import * as path from 'path'
import * as os from 'os'
import { BrowserWindow } from 'electron'
import { loadSettings, Settings } from './settings-store'

export interface ICloudConfig {
  activeProjectId?: string
  activeProjectName?: string
  settings?: Partial<Settings>
  lastSync?: string
}

function getICloudConfigPath(icloudPath: string): string {
  return path.join(icloudPath, 'EditHub', 'config.json')
}

function tryGetICloudPathFromRegistry(): string | null {
  if (process.platform !== 'win32') return null
  try {
    // Dynamic require for Windows-only module
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { execSync } = require('child_process')
    const result = execSync(
      'reg query "HKCU\\Software\\Apple Inc.\\Internet Services" /v ICDrive 2>nul',
      { encoding: 'utf-8' }
    )
    const match = result.match(/ICDrive\s+REG_SZ\s+(.+)/)
    if (match) return match[1].trim()
  } catch {}
  return null
}

export class ICloudSync {
  private mainWindow: BrowserWindow | null
  private syncInterval: NodeJS.Timeout | null = null
  private icloudPath: string
  private config: ICloudConfig = {}

  constructor(mainWindow: BrowserWindow | null) {
    this.mainWindow = mainWindow
    const settings = loadSettings()
    this.icloudPath = this.resolveICloudPath(settings.icloudPath)
  }

  private resolveICloudPath(configuredPath: string): string {
    // Try registry on Windows
    const fromRegistry = tryGetICloudPathFromRegistry()
    if (fromRegistry && fs.existsSync(fromRegistry)) return fromRegistry

    if (configuredPath && fs.existsSync(configuredPath)) return configuredPath

    // Fallbacks
    const candidates = [
      path.join(os.homedir(), 'iCloudDrive'),
      path.join(os.homedir(), 'Library', 'Mobile Documents', 'com~apple~CloudDocs'),
      'C:\\Users\\' + os.userInfo().username + '\\iCloudDrive',
    ]
    for (const c of candidates) {
      if (fs.existsSync(c)) return c
    }

    return configuredPath // Use configured even if not found yet
  }

  private getConfigPath(): string {
    return getICloudConfigPath(this.icloudPath)
  }

  private ensureICloudFolders(): void {
    const folders = [
      path.join(this.icloudPath, 'EditHub'),
      path.join(this.icloudPath, 'EditHub', 'projects'),
      path.join(this.icloudPath, 'EditHub', 'archive'),
    ]
    for (const f of folders) {
      try {
        if (!fs.existsSync(f)) {
          fs.mkdirSync(f, { recursive: true })
        }
      } catch {}
    }
  }

  readConfig(): ICloudConfig {
    try {
      const configPath = this.getConfigPath()
      if (fs.existsSync(configPath)) {
        const raw = fs.readFileSync(configPath, 'utf-8')
        return JSON.parse(raw)
      }
    } catch (err) {
      console.warn('Failed to read iCloud config:', err)
    }
    return {}
  }

  writeConfig(config: Partial<ICloudConfig>): void {
    try {
      this.ensureICloudFolders()
      const configPath = this.getConfigPath()
      const current = this.readConfig()
      const updated = { ...current, ...config, lastSync: new Date().toISOString() }
      fs.writeFileSync(configPath, JSON.stringify(updated, null, 2), 'utf-8')
      this.config = updated
    } catch (err) {
      console.warn('Failed to write iCloud config:', err)
    }
  }

  setActiveProject(projectId: string, projectName: string): void {
    this.writeConfig({ activeProjectId: projectId, activeProjectName: projectName })
  }

  getArchiveFolder(): string {
    return path.join(this.icloudPath, 'EditHub', 'archive')
  }

  getProjectsFolder(): string {
    return path.join(this.icloudPath, 'EditHub', 'projects')
  }

  isSyncing(): boolean {
    // iCloud for Windows creates .icloud placeholder files for not-yet-downloaded files.
    // We also check for very recently modified files (being uploaded) by looking at
    // mtime compared to now — files modified in the last 30s are likely being synced.
    try {
      const editHubFolder = path.join(this.icloudPath, 'EditHub')
      if (!fs.existsSync(editHubFolder)) return false
      const now = Date.now()

      const checkFolder = (dir: string, depth = 0): boolean => {
        if (depth > 4) return false
        try {
          const entries = fs.readdirSync(dir, { withFileTypes: true })
          for (const entry of entries) {
            // .icloud file = placeholder = downloading from cloud
            if (entry.name.endsWith('.icloud')) return true
            const fullPath = path.join(dir, entry.name)
            try {
              const stat = fs.statSync(fullPath)
              // File modified in last 60s = likely uploading
              if (!stat.isDirectory() && now - stat.mtimeMs < 60_000) return true
              if (stat.isDirectory() && checkFolder(fullPath, depth + 1)) return true
            } catch {}
          }
        } catch {}
        return false
      }

      return checkFolder(editHubFolder)
    } catch {
      return false
    }
  }

  getUploadingProjects(): string[] {
    // Returns folder names of projects currently being uploaded to iCloud
    const uploading: string[] = []
    try {
      const archiveFolder = path.join(this.icloudPath, 'EditHub', 'archive')
      if (!fs.existsSync(archiveFolder)) return []
      const now = Date.now()
      const entries = fs.readdirSync(archiveFolder, { withFileTypes: true })
      for (const entry of entries) {
        if (!entry.isDirectory()) continue
        const folderPath = path.join(archiveFolder, entry.name)
        try {
          const stat = fs.statSync(folderPath)
          // Folder modified in last 5 min = likely being synced
          if (now - stat.mtimeMs < 5 * 60_000) {
            uploading.push(entry.name)
          }
        } catch {}
      }
    } catch {}
    return uploading
  }

  start(): void {
    // Initial config read
    try {
      this.config = this.readConfig()
    } catch {}

    // Sync status check every 10 seconds
    this.syncInterval = setInterval(() => {
      const syncing = this.isSyncing()
      this.mainWindow?.webContents.send('icloud:status', { syncing })
    }, 10000)
  }

  updateSettings(settings: Settings): void {
    this.icloudPath = this.resolveICloudPath(settings.icloudPath)
  }

  stop(): void {
    if (this.syncInterval) {
      clearInterval(this.syncInterval)
      this.syncInterval = null
    }
  }
}
