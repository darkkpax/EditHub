import { IpcMain, BrowserWindow, nativeImage } from 'electron'
import * as fs from 'fs'
import * as path from 'path'
import {
  listProjectsInFolder,
  listArchivedProjectsInFolder,
  listProjectFolders,
  findProjectPreviewVideo,
  createProjectFolderStructure,
  createProjectInfo,
  readProjectInfo,
  writeProjectInfo,
  extractArchivesToProjects,
  ProjectInfo,
} from '../services/project-store'
import { Downloader } from '../services/downloader'
import { loadSettings } from '../services/settings-store'
import { launchDaVinci } from '../services/davinci'
import { ICloudSync } from '../services/icloud'
import { Archiver } from '../services/archiver'
import { FileWatcher } from '../services/watcher'
import { spawnSync } from 'child_process'

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

  function sendToAll(channel: string, payload: unknown): void {
    BrowserWindow.getAllWindows().forEach((window) => {
      window.webContents.send(channel, payload)
    })
  }

  // LIST PROJECTS
  ipcMain.handle('projects:list', async () => {
    const settings = loadSettings()
    const folder = settings.projectsFolder

    if (!fs.existsSync(folder)) {
      try { fs.mkdirSync(folder, { recursive: true }) } catch {}
    }

    const seen = new Set<string>()
    const projects = listProjectsInFolder(folder).filter((p) => {
      if (seen.has(p.id)) return false
      seen.add(p.id)
      return true
    })

    // Also scan iCloudDrive/EditHub/Videos — primary long-term storage
    const icloudVideos = path.join(settings.icloudPath, 'EditHub', 'Videos')
    if (fs.existsSync(icloudVideos)) {
      const icloudProjects = listProjectsInFolder(icloudVideos).filter((p) => {
        if (seen.has(p.id)) return false
        seen.add(p.id)
        return true
      })
      projects.push(...icloudProjects)
    }

    return projects
  })

  ipcMain.handle('projects:folders', async (_e, { projectPath }: { projectPath: string }) => {
    return listProjectFolders(projectPath)
  })

  ipcMain.handle('projects:thumbnail', async (_e, { projectPath }: { projectPath: string }) => {
    const videoPath = findProjectPreviewVideo(projectPath)
    if (!videoPath) return null

    try {
      const image = await nativeImage.createThumbnailFromPath(videoPath, { width: 360, height: 220 })
      if (!image.isEmpty()) {
        return { videoPath, dataUrl: image.toDataURL() }
      }
    } catch {}

    const ffmpeg = spawnSync('where', ['ffmpeg'], { encoding: 'utf-8' })
    if (ffmpeg.status !== 0) return { videoPath, dataUrl: null }

    const exe = ffmpeg.stdout.split(/\r?\n/).find(Boolean)
    if (!exe) return { videoPath, dataUrl: null }

    const result = spawnSync(exe, [
      '-hide_banner',
      '-loglevel', 'error',
      '-ss', '00:00:01',
      '-i', videoPath,
      '-frames:v', '1',
      '-vf', 'scale=360:-1',
      '-f', 'image2pipe',
      '-vcodec', 'png',
      'pipe:1',
    ], { encoding: 'buffer', maxBuffer: 8 * 1024 * 1024 })

    if (result.status !== 0 || !result.stdout?.length) return { videoPath, dataUrl: null }
    return { videoPath, dataUrl: `data:image/png;base64,${result.stdout.toString('base64')}` }
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
        const footageFolder = path.join(projectFolder, 'FOOTAGE')
        if (!activeDownloader) {
          activeDownloader = new Downloader(
            (progress) => {
              sendToAll('download:progress', progress)

              // Update project info with progress
              const projectInfo = readProjectInfo(projectFolder)
              if (projectInfo) {
                projectInfo.downloadProgress[progress.fileUrl] = progress.percent
                projectInfo.status = 'downloading'
                writeProjectInfo(projectFolder, projectInfo)
              }
            },
            (projectId) => {
              sendToAll('download:complete', { projectId })
              const projectInfo = readProjectInfo(projectFolder)
              if (projectInfo) {
                projectInfo.status = 'ready'
                projectInfo.downloadProgress = {}
                writeProjectInfo(projectFolder, projectInfo)
              }
            },
            (projectId, error) => {
              sendToAll('download:error', { projectId, error })
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
    sendToAll('active:changed', { projectId: project.id })

    // Launch DaVinci and open/create the matching Resolve project.
    const launchResult = await launchDaVinci(settings.davinciPath, project.folderPath)

    return { ...launchResult, project }
  })

  // ARCHIVE PROJECT (сгрузить в iCloudDrive/EditHub/Videos)
  ipcMain.handle('projects:archive', async (_e, { id }: { id: string }) => {
    const settings = loadSettings()
    const projects = listProjectsInFolder(settings.projectsFolder)
    const project = projects.find((p) => p.id === id)

    if (!project || !project.folderPath) {
      throw new Error('Project not found')
    }

    // Destination: iCloudDrive/EditHub/Videos/{year}/{month}/
    const icloudVideos = path.join(settings.icloudPath, 'EditHub', 'Videos')
    if (archiver) {
      await archiver.archiveProject(project.folderPath, icloudVideos)
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

  // EXTRACT ARCHIVES (background, non-blocking)
  ipcMain.handle('projects:extractArchives', async () => {
    const settings = loadSettings()
    const sourceFolders: string[] = []

    if (icloudSync) {
      const archiveFolder = icloudSync.getArchiveFolder()
      if (fs.existsSync(archiveFolder)) sourceFolders.push(archiveFolder)
    }
    if (settings.icloudPath) {
      const icloudVideos = path.join(settings.icloudPath, 'EditHub', 'Videos')
      if (fs.existsSync(icloudVideos)) sourceFolders.push(icloudVideos)
      // Also check iCloudDrive root directly (for year/month structure at root)
      if (fs.existsSync(settings.icloudPath)) sourceFolders.push(settings.icloudPath)
    }
    if (fs.existsSync(settings.projectsFolder)) {
      sourceFolders.push(settings.projectsFolder)
    }

    // Run in background — don't await, return immediately
    extractArchivesToProjects(
      sourceFolders,
      (p) => mainWindow?.webContents.send('archives:progress', p)
    ).then((result) => {
      mainWindow?.webContents.send('archives:done', result)
    }).catch(() => {
      mainWindow?.webContents.send('archives:done', { extracted: 0, total: 0 })
    })

    return { started: true }
  })

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
