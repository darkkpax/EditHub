import chokidar, { FSWatcher } from 'chokidar'
import * as path from 'path'
import * as fs from 'fs'
import { BrowserWindow } from 'electron'
import { sortFileIntoProject } from './sorter'

function matchesPatterns(fileName: string, patterns: string[]): boolean {
  return patterns.some((pattern) => {
    const regexStr = pattern
      .replace(/[.+^${}()|[\]\\]/g, '\\$&')
      .replace(/\*/g, '.*')
    const regex = new RegExp(regexStr, 'i')
    return regex.test(fileName)
  })
}

// Subfolders that are "managed" — files already inside them don't need sorting
const MANAGED_SUBFOLDERS = new Set(['SFX', 'Music', 'Footage', 'Graphics', 'Docs'])

// Files/dirs to ignore inside project folders
const IGNORE_NAMES = new Set(['.edithub.json', '.DS_Store', 'Thumbs.db', 'desktop.ini'])

export class FileWatcher {
  private activeProjectWatcher: FSWatcher | null = null
  private downloadsWatcher: FSWatcher | null = null
  private mainWindow: BrowserWindow | null
  private activeProjectId: string | null = null
  private activeProjectRoot: string | null = null
  private settleTimers = new Map<string, NodeJS.Timeout>()

  constructor(mainWindow: BrowserWindow | null) {
    this.mainWindow = mainWindow
  }

  setActiveProject(projectId: string, projectRoot: string): void {
    this.activeProjectId = projectId
    this.activeProjectRoot = projectRoot
    // Re-watch whenever active project changes
    this.watchActiveProject(projectRoot)
  }

  private watchActiveProject(projectRoot: string): void {
    if (this.activeProjectWatcher) {
      this.activeProjectWatcher.close()
      this.activeProjectWatcher = null
    }

    if (!projectRoot || !fs.existsSync(projectRoot)) return

    this.activeProjectWatcher = chokidar.watch(projectRoot, {
      depth: 0, // Only watch root of the project folder
      ignoreInitial: true,
      awaitWriteFinish: {
        stabilityThreshold: 1500,
        pollInterval: 300,
      },
      ignored: (filePath: string) => {
        const name = path.basename(filePath)
        return IGNORE_NAMES.has(name) || name.startsWith('.')
      },
    })

    this.activeProjectWatcher.on('add', (filePath: string) => {
      if (!this.activeProjectRoot || !this.activeProjectId) return

      // Only act on files dropped directly at the project root (not in subfolders)
      const rel = path.relative(this.activeProjectRoot, filePath)
      const parts = rel.split(path.sep)
      if (parts.length !== 1) return // Already in subfolder

      const name = path.basename(filePath)
      if (IGNORE_NAMES.has(name) || name.endsWith('.drp')) return

      sortFileIntoProject(
        filePath,
        this.activeProjectRoot,
        this.activeProjectId,
        (from, to) => {
          this.mainWindow?.webContents.send('file:sorted', {
            projectId: this.activeProjectId,
            from,
            to,
          })
        }
      )
    })

    this.activeProjectWatcher.on('error', (err) => {
      console.warn('Project watcher error:', err)
    })
  }

  watchProjectsFolder(projectsFolder: string): void {
    // Watch all project root folders for file drops.
    // Each project subfolder is watched separately when it becomes active.
    // This watcher just ensures we pick up changes across all projects
    // for status updates (size recalculation etc.) — but sorting only
    // happens for the ACTIVE project via watchActiveProject.
    if (!fs.existsSync(projectsFolder)) return
  }

  watchDownloadsFolder(downloadsFolder: string, patterns: string[]): void {
    if (this.downloadsWatcher) {
      this.downloadsWatcher.close()
      this.downloadsWatcher = null
    }

    if (!downloadsFolder || !fs.existsSync(downloadsFolder)) return

    this.downloadsWatcher = chokidar.watch(downloadsFolder, {
      depth: 0,
      ignoreInitial: true,
    })

    this.downloadsWatcher.on('add', (filePath: string) => {
      const fileName = path.basename(filePath)

      if (!matchesPatterns(fileName, patterns)) return

      // Settle delay — wait for browser to finish writing
      const existingTimer = this.settleTimers.get(filePath)
      if (existingTimer) clearTimeout(existingTimer)

      const timer = setTimeout(() => {
        this.settleTimers.delete(filePath)
        try {
          if (!fs.existsSync(filePath)) return
          const stat1 = fs.statSync(filePath)
          setTimeout(() => {
            try {
              if (!fs.existsSync(filePath)) return
              const stat2 = fs.statSync(filePath)
              if (stat1.size === stat2.size && stat2.size > 0) {
                this.mainWindow?.webContents.send('downloads:matched', {
                  fileName,
                  filePath,
                })
              }
            } catch {}
          }, 1000)
        } catch {}
      }, 2000)

      this.settleTimers.set(filePath, timer)
    })

    this.downloadsWatcher.on('error', (err) => {
      console.warn('Downloads watcher error:', err)
    })
  }

  updateSettings(settings: { projectsFolder?: string; downloadsFolder?: string; autoImportPatterns?: string[] }): void {
    if (settings.projectsFolder) {
      this.watchProjectsFolder(settings.projectsFolder)
    }
    if (settings.downloadsFolder) {
      this.watchDownloadsFolder(
        settings.downloadsFolder,
        settings.autoImportPatterns || ['-enhanced', '-enhanced-v2']
      )
    }
  }

  stop(): void {
    this.activeProjectWatcher?.close()
    this.downloadsWatcher?.close()
    this.settleTimers.forEach((t) => clearTimeout(t))
    this.settleTimers.clear()
  }
}
