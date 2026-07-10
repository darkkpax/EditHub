import * as fs from 'fs'
import * as path from 'path'
import { BrowserWindow } from 'electron'
import { spawnSync } from 'child_process'
import { loadSettings } from './settings-store'
import { listProjectsInFolder, readProjectInfo } from './project-store'
import { exportDaVinciProject } from './davinci'
import { removeFootage } from './archive-files'

const CHECK_INTERVAL_MS = 60 * 60 * 1000 // 1 hour

function setCloudPinState(targetPath: string, onlineOnly: boolean): boolean {
  if (process.platform !== 'win32') return false
  if (!fs.existsSync(targetPath)) return false

  const args = onlineOnly
    ? ['+U', '-P', '/S', '/D', targetPath]
    : ['-U', '+P', '/S', '/D', targetPath]

  try {
    const result = spawnSync('attrib.exe', args, {
      windowsHide: true,
      encoding: 'utf-8',
      timeout: 5 * 60 * 1000,
    })
    if (result.status === 0) return true

    const message = (result.stderr || result.stdout || '').trim()
    if (message) {
      console.warn(`Cloud pin state update failed for ${targetPath}: ${message}`)
    }
  } catch (err) {
    console.warn(`Cloud pin state update failed for ${targetPath}:`, err)
  }
  return false
}
export class Archiver {
  private mainWindow: BrowserWindow | null
  private intervalHandle: NodeJS.Timeout | null = null
  private autoArchiveDays: number = 30

  constructor(mainWindow: BrowserWindow | null) {
    this.mainWindow = mainWindow
  }

  start(autoArchiveDays: number): void {
    this.autoArchiveDays = autoArchiveDays
    this.intervalHandle = setInterval(() => {
      this.runAutoArchive().catch((err) => {
        console.warn('Auto-archive error:', err)
      })
    }, CHECK_INTERVAL_MS)
  }

  updateAutoArchiveDays(days: number): void {
    this.autoArchiveDays = days
  }

  async runAutoArchive(): Promise<void> {
    const settings = loadSettings()
    const { projectsFolder, icloudPath } = settings

    if (!projectsFolder || !fs.existsSync(projectsFolder)) return

    const archiveFolder = path.join(icloudPath, 'EditHub', 'Videos')
    const thresholdMs = this.autoArchiveDays * 24 * 60 * 60 * 1000
    const now = new Date()
    const currentYear = now.getFullYear().toString()
    const currentMonth = now.toLocaleString('en-US', { month: 'long' }).toUpperCase()

    try {
      const projects = listProjectsInFolder(projectsFolder)
      for (const projectInfo of projects) {
        if (!projectInfo.folderPath) continue
        if (projectInfo.status === 'active') continue

        const isCurrentMonth =
          projectInfo.year === currentYear &&
          projectInfo.month?.toUpperCase() === currentMonth

        const lastOpened = projectInfo.lastOpenedAt
          ? new Date(projectInfo.lastOpenedAt).getTime()
          : new Date(projectInfo.createdAt).getTime()

        const age = Date.now() - lastOpened

        if (!isCurrentMonth || age >= thresholdMs) {
          await this.archiveProject(projectInfo.folderPath, archiveFolder)
        }
      }
    } catch (err) {
      console.warn('Auto-archive scan error:', err)
    }
  }

  async archiveProject(
    projectFolder: string,
    archiveFolder: string
  ): Promise<void> {
    try {
      if (!fs.existsSync(archiveFolder)) {
        fs.mkdirSync(archiveFolder, { recursive: true })
      }

      const info = readProjectInfo(projectFolder)
      const folderName = path.basename(projectFolder)
      const exportResult = await exportDaVinciProject(projectFolder)
      if (!exportResult.exported) {
        console.warn(`Could not export DaVinci project before archive: ${exportResult.message || folderName}`)
      }

      const destRoot = info?.year && info?.month
        ? path.join(archiveFolder, info.year, info.month)
        : archiveFolder
      fs.mkdirSync(destRoot, { recursive: true })

      const destPath = path.join(destRoot, folderName)

      // Handle name collision
      let finalDest = destPath
      if (fs.existsSync(destPath)) {
        finalDest = path.join(destRoot, `${folderName}_${Date.now()}`)
      }

      fs.renameSync(projectFolder, finalDest)
      removeFootage(finalDest)
      setCloudPinState(finalDest, true)
      console.log(`Archived project: ${folderName} -> ${finalDest}`)
    } catch (err) {
      console.warn(`Failed to archive project ${projectFolder}:`, err)
      throw err
    }
  }

  async restoreFromArchive(
    archivePath: string,
    projectsFolder: string
  ): Promise<void> {
    if (!fs.existsSync(archivePath)) {
      throw new Error('Archive folder not found')
    }

    const folderName = path.basename(archivePath)
    const parent = path.dirname(archivePath)
    const month = path.basename(parent)
    const year = path.basename(path.dirname(parent))
    const destRoot = /^\d{4}$/.test(year) && month
      ? path.join(projectsFolder, year, month)
      : projectsFolder
    fs.mkdirSync(destRoot, { recursive: true })

    const destPath = path.join(destRoot, folderName)

    let finalDest = destPath
    if (fs.existsSync(destPath)) {
      finalDest = path.join(destRoot, `${folderName}_restored_${Date.now()}`)
    }

    fs.renameSync(archivePath, finalDest)
    setCloudPinState(finalDest, false)
  }

  stop(): void {
    if (this.intervalHandle) {
      clearInterval(this.intervalHandle)
      this.intervalHandle = null
    }
  }
}
