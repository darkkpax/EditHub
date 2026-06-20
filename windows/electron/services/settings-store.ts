import * as fs from 'fs'
import * as path from 'path'
import * as os from 'os'

export interface Settings {
  projectsFolder: string
  downloadsFolder: string
  dropfxLibrary: string
  davinciPath: string
  autoArchiveDays: number
  autoImportPatterns: string[]
  icloudPath: string
}

function getDefaultICloudPath(): string {
  if (process.platform === 'win32') {
    // iCloud for Windows typically mounts here
    return path.join(os.homedir(), 'iCloudDrive')
  }
  return path.join(os.homedir(), 'Library', 'Mobile Documents', 'com~apple~CloudDocs')
}

function getDefaultDaVinciPath(): string {
  if (process.platform === 'win32') {
    return 'C:\\Program Files\\Blackmagic Design\\DaVinci Resolve\\Resolve.exe'
  }
  return '/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/MacOS/Resolve'
}

const defaultSettings: Settings = {
  projectsFolder: path.join(os.homedir(), 'EditHub', 'Projects'),
  downloadsFolder: path.join(os.homedir(), 'Downloads'),
  dropfxLibrary: path.join(os.homedir(), 'EditHub', 'SFX'),
  davinciPath: getDefaultDaVinciPath(),
  autoArchiveDays: 30,
  autoImportPatterns: ['*-enhanced*', '*-enhanced-v2*'],
  icloudPath: getDefaultICloudPath(),
}

const settingsPath = path.join(os.homedir(), '.edithub', 'settings.json')

export function loadSettings(): Settings {
  try {
    if (fs.existsSync(settingsPath)) {
      const raw = fs.readFileSync(settingsPath, 'utf-8')
      const parsed = JSON.parse(raw)
      return { ...defaultSettings, ...parsed }
    }
  } catch (err) {
    console.warn('Failed to load settings:', err)
  }
  return { ...defaultSettings }
}

export function saveSettings(settings: Settings): void {
  try {
    const dir = path.dirname(settingsPath)
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true })
    }
    fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2), 'utf-8')
  } catch (err) {
    console.error('Failed to save settings:', err)
  }
}

export function updateSettings(partial: Partial<Settings>): Settings {
  const current = loadSettings()
  const updated = { ...current, ...partial }
  saveSettings(updated)
  return updated
}
