import * as fs from 'fs'
import * as path from 'path'
import { BrowserWindow } from 'electron'
import { loadSettings } from './settings-store'
import { ProjectInfo, readProjectInfo } from './project-store'

const CHECK_INTERVAL_MS = 60 * 60 * 1000 // 1 hour

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

    const archiveFolder = path.join(icloudPath, 'EditHub', 'archive')
    const thresholdMs = this.autoArchiveDays * 24 * 60 * 60 * 1000

    try {
      const entries = fs.readdirSync(projectsFolder, { withFileTypes: true })
      for (const entry of entries) {
        if (!entry.isDirectory()) continue
        const projectFolder = path.join(projectsFolder, entry.name)
        const projectInfo = readProjectInfo(projectFolder)

        if (!projectInfo) continue

        // Don't archive active projects
        if (projectInfo.status === 'active') continue

        const lastOpened = projectInfo.lastOpenedAt
          ? new Date(projectInfo.lastOpenedAt).getTime()
          : new Date(projectInfo.createdAt).getTime()

        const age = Date.now() - lastOpened

        if (age >= thresholdMs) {
          await this.archiveProject(projectFolder, archiveFolder)
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

      const folderName = path.basename(projectFolder)
      const destPath = path.join(archiveFolder, folderName)

      // Handle name collision
      let finalDest = destPath
      if (fs.existsSync(destPath)) {
        finalDest = path.join(archiveFolder, `${folderName}_${Date.now()}`)
      }

      fs.renameSync(projectFolder, finalDest)
      console.log(`Archived project: ${folderName} → ${finalDest}`)
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
    const destPath = path.join(projectsFolder, folderName)

    let finalDest = destPath
    if (fs.existsSync(destPath)) {
      finalDest = path.join(projectsFolder, `${folderName}_restored_${Date.now()}`)
    }

    fs.renameSync(archivePath, finalDest)
  }

  stop(): void {
    if (this.intervalHandle) {
      clearInterval(this.intervalHandle)
      this.intervalHandle = null
    }
  }
}
