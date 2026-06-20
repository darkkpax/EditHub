import { IpcMain, BrowserWindow } from 'electron'
import * as fs from 'fs'
import * as path from 'path'
import AdmZip from 'adm-zip'
import {
  listProjectsInFolder,
  createProjectFolderStructure,
  createProjectInfo,
  readProjectInfo,
  writeProjectInfo,
  ProjectInfo,
} from '../services/project-store'
import { Downloader } from '../services/downloader'
import { loadSettings } from '../services/settings-store'
import { launchDaVinci, findDrpFile } from '../services/davinci'
import { ICloudSync } from '../services/icloud'
import { Archiver } from '../services/archiver'
import { FileWatcher } from '../services/watcher'

let activeDownloader: Downloader | null = null
let icloudSync: ICloudSync | null = null
let archiver: Archiver | null = null
let fileWatcher: FileWatcher | null = null

export function setupProjectsIPC(
  ipcMain: IpcMain,
  mainWindow: BrowserWindow | null,
  watcher?: FileWatcher | null
): void {
  fileWatcher = watcher || null
  icloudSync = new ICloudSync(mainWindow)
  archiver = new Archiver(mainWindow)

  function getProjectsFolder(): string {
    const settings = loadSettings()
    return settings.projectsFolder
  }

  // LIST PROJECTS
  ipcMain.handle('projects:list', async () => {
    const folder = getProjectsFolder()

    if (!fs.existsSync(folder)) {
      try {
        fs.mkdirSync(folder, { recursive: true })
      } catch {}
      return []
    }

    const projects = listProjectsInFolder(folder)

    // Also scan iCloud archive for archived projects
    if (icloudSync) {
      const archiveFolder = icloudSync.getArchiveFolder()
      if (fs.existsSync(archiveFolder)) {
        const archived = listProjectsInFolder(archiveFolder)
        archived.forEach((p) => (p.status = 'archive'))
        projects.push(...archived)
      }
    }

    return projects
  })

  // CREATE PROJECT
  ipcMain.handle(
    'projects:create',
    async (_e, { name, urls }: { name: string; urls: string[] }) => {
      const folder = getProjectsFolder()
      if (!fs.existsSync(folder)) {
        fs.mkdirSync(folder, { recursive: true })
      }

      const projectFolder = createProjectFolderStructure(folder, name)
      const info = createProjectInfo(name, urls)
      writeProjectInfo(projectFolder, info)

      if (urls.length > 0) {
        // Start downloads
        const footageFolder = path.join(projectFolder, 'Footage')
        if (!activeDownloader) {
          activeDownloader = new Downloader(
            (progress) => {
              mainWindow?.webContents.send('download:progress', progress)

              // Update project info with progress
              const projectInfo = readProjectInfo(projectFolder)
              if (projectInfo) {
                projectInfo.downloadProgress[progress.fileUrl] = progress.percent
                projectInfo.status = 'downloading'
                writeProjectInfo(projectFolder, projectInfo)
              }
            },
            (projectId) => {
              mainWindow?.webContents.send('download:complete', { projectId })
              const projectInfo = readProjectInfo(projectFolder)
              if (projectInfo) {
                projectInfo.status = 'ready'
                projectInfo.downloadProgress = {}
                writeProjectInfo(projectFolder, projectInfo)
              }
            },
            (projectId, error) => {
              mainWindow?.webContents.send('download:error', { projectId, error })
              const projectInfo = readProjectInfo(projectFolder)
              if (projectInfo) {
                projectInfo.status = 'ready'
                writeProjectInfo(projectFolder, projectInfo)
              }
            }
          )
        }

        activeDownloader
          .startDownloads(info.id, urls, footageFolder)
          .catch((err) => {
            console.error('Download failed:', err)
          })
      }

      return { ...info, folderPath: projectFolder }
    }
  )

  // OPEN PROJECT (launch DaVinci)
  ipcMain.handle('projects:open', async (_e, { id }: { id: string }) => {
    const folder = getProjectsFolder()
    const settings = loadSettings()

    // Find the project folder by id
    const projects = listProjectsInFolder(folder)
    const project = projects.find((p) => p.id === id)

    if (!project || !project.folderPath) {
      throw new Error('Project not found')
    }

    // Update last opened
    project.lastOpenedAt = new Date().toISOString()
    project.status = 'active'
    writeProjectInfo(project.folderPath, project)

    // Update iCloud active project
    icloudSync?.setActiveProject(project.id, project.name)

    // Tell file watcher which project is now active (for auto-sort)
    if (project.folderPath) {
      fileWatcher?.setActiveProject(project.id, project.folderPath)
    }

    // Notify renderer
    mainWindow?.webContents.send('active:changed', { projectId: project.id })

    // Launch DaVinci
    const drpFile = findDrpFile(project.folderPath)
    const launched = launchDaVinci(settings.davinciPath, drpFile || undefined)

    return { launched, project }
  })

  // ARCHIVE PROJECT
  ipcMain.handle('projects:archive', async (_e, { id }: { id: string }) => {
    const folder = getProjectsFolder()
    const projects = listProjectsInFolder(folder)
    const project = projects.find((p) => p.id === id)

    if (!project || !project.folderPath) {
      throw new Error('Project not found')
    }

    if (!icloudSync) throw new Error('iCloud sync not initialized')

    const archiveFolder = icloudSync.getArchiveFolder()
    if (archiver) {
      await archiver.archiveProject(project.folderPath, archiveFolder)
    }

    return { success: true }
  })

  // DELETE PROJECT
  ipcMain.handle('projects:delete', async (_e, { id }: { id: string }) => {
    const folder = getProjectsFolder()
    const projects = listProjectsInFolder(folder)
    const project = projects.find((p) => p.id === id)

    if (!project || !project.folderPath) {
      throw new Error('Project not found')
    }

    // Cancel any downloads
    activeDownloader?.cancelDownload(id)

    // Delete folder
    fs.rmSync(project.folderPath, { recursive: true, force: true })

    return { success: true }
  })

  // CANCEL DOWNLOADS
  ipcMain.handle(
    'downloads:cancel',
    async (_e, { projectId }: { projectId: string }) => {
      activeDownloader?.cancelDownload(projectId)

      // Update project status
      const folder = getProjectsFolder()
      const projects = listProjectsInFolder(folder)
      const project = projects.find((p) => p.id === projectId)
      if (project && project.folderPath) {
        project.status = 'ready'
        project.downloadProgress = {}
        writeProjectInfo(project.folderPath, project)
      }

      return { success: true }
    }
  )

  // RESTORE FROM ARCHIVE
  ipcMain.handle(
    'projects:restore',
    async (_e, { id }: { id: string }) => {
      if (!icloudSync) throw new Error('iCloud sync not initialized')

      const archiveFolder = icloudSync.getArchiveFolder()
      const archivedProjects = listProjectsInFolder(archiveFolder)
      const project = archivedProjects.find((p) => p.id === id)

      if (!project || !project.folderPath) {
        throw new Error('Archived project not found')
      }

      const settings = loadSettings()
      await archiver?.restoreFromArchive(project.folderPath, settings.projectsFolder)

      return { success: true }
    }
  )
}
