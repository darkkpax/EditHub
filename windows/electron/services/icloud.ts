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

export interface ICloudAuthConfig {
  serverURL: string
  token?: string
  userEmail?: string
  workspaceId?: string
  lastSync?: string
}

function getICloudConfigPath(icloudPath: string): string {
  return path.join(icloudPath, 'EditHub', 'config.json')
}

function getICloudAuthPath(icloudPath: string): string {
  return path.join(icloudPath, 'EditHub', 'auth.json')
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
      path.join(this.icloudPath, 'EditHub', 'Videos'),
      path.join(this.icloudPath, 'EditHub', 'projects'),
      path.join(this.icloudPath, 'EditHub', 'Archive'),
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
      this.ensureAuthFile()
      this.config = updated
    } catch (err) {
      console.warn('Failed to write iCloud config:', err)
    }
  }

  setActiveProject(projectId: string, projectName: string): void {
    this.writeConfig({ activeProjectId: projectId, activeProjectName: projectName })
  }

  /**
   * The single source of truth for where archived ("сгруженные") projects
   * live in iCloud. Both the Mac app and the Windows archiver use
   * `iCloudDrive/EditHub/Videos/{year}/{month}/`, so the sync monitor, restore and
   * upload-status logic must all point here too.
   */
  getArchiveFolder(): string {
    return path.join(this.icloudPath, 'EditHub', 'Videos')
  }

  getProjectsFolder(): string {
    return path.join(this.icloudPath, 'EditHub', 'projects')
  }

  isSyncing(): boolean {
    // iCloud for Windows creates .icloud placeholder files for not-yet-downloaded files.
    // We also check for very recently modified files (being uploaded) by looking at
    // mtime compared to now — files modified in the last 30s are likely being synced.
    try {
      const archiveRoot = this.getArchiveFolder()
      if (!fs.existsSync(archiveRoot)) return false
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

      return checkFolder(archiveRoot)
    } catch {
      return false
    }
  }

  getUploadingProjects(): string[] {
    // Returns folder names of projects currently being uploaded to iCloud.
    // Archived projects live under EditHub/Videos/{year}/{month}/{project}, so we
    // look at the leaf project folders rather than the archive root.
    const uploading: string[] = []
    try {
      const archiveFolder = this.getArchiveFolder()
      if (!fs.existsSync(archiveFolder)) return []
      const now = Date.now()
      const recent = (p: string): boolean => {
        try { return now - fs.statSync(p).mtimeMs < 5 * 60_000 } catch { return false }
      }
      const dirs = (p: string): string[] => {
        try {
          return fs.readdirSync(p, { withFileTypes: true })
            .filter((e) => e.isDirectory() && !e.name.toLowerCase().startsWith('__extracting_'))
            .map((e) => e.name)
        } catch { return [] }
      }
      for (const year of dirs(archiveFolder)) {
        const yearPath = path.join(archiveFolder, year)
        for (const month of dirs(yearPath)) {
          const monthPath = path.join(yearPath, month)
          for (const project of dirs(monthPath)) {
            if (recent(path.join(monthPath, project))) uploading.push(project)
          }
        }
      }
    } catch {}
    return uploading
  }

  start(): void {
    this.ensureICloudFolders()
    this.ensureAuthFile()
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

  private ensureAuthFile(): void {
    try {
      this.ensureICloudFolders()
      const authPath = getICloudAuthPath(this.icloudPath)
      if (fs.existsSync(authPath)) return
      const auth: ICloudAuthConfig = {
        serverURL: 'http://127.0.0.1:3000',
        lastSync: new Date().toISOString(),
      }
      fs.writeFileSync(authPath, JSON.stringify(auth, null, 2), 'utf-8')
    } catch (err) {
      console.warn('Failed to ensure iCloud auth file:', err)
    }
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
