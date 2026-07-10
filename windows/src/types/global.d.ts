export {}

declare module 'react' {
  interface CSSProperties {
    WebkitAppRegion?: 'drag' | 'no-drag'
  }
}

declare global {
  interface Window {
    edithub: {
      debugLog?: (level: 'INFO' | 'WARN' | 'ERROR', message: string, details?: unknown) => void
      listProjects: () => Promise<ProjectInfo[]>
      listProjectFolders: (projectPath: string) => Promise<FolderEntry[]>
      getProjectThumbnail: (projectPath: string) => Promise<{ videoPath: string; dataUrl: string | null } | null>
      createProject: (name: string, urls: string[]) => Promise<ProjectInfo>
      openProject: (id: string) => Promise<DaVinciOpenResult>
      archiveProject: (id: string) => Promise<void>
      restoreProject: (id: string) => Promise<void>
      deleteProject: (id: string) => Promise<void>
      cancelDownload: (projectId: string) => Promise<void>
      getSettings: () => Promise<AppSettings>
      setSettings: (settings: Partial<AppSettings>) => Promise<void>
      pickFolder: () => Promise<string | null>
      showInExplorer: (filePath: string) => Promise<void>
      minimizeWindow: () => Promise<void>
      closeWindow: () => Promise<void>
      onDownloadProgress: (cb: (data: DownloadProgressData) => void) => () => void
      onDownloadComplete: (cb: (data: { projectId: string }) => void) => () => void
      onDownloadError: (cb: (data: { projectId: string; error: string }) => void) => () => void
      onFileSorted: (cb: (data: { projectId: string; from: string; to: string }) => void) => () => void
      onDownloadsMatched: (cb: (data: { fileName: string; filePath: string }) => void) => () => void
      onICloudStatus: (cb: (data: { syncing: boolean }) => void) => () => void
      onActiveChanged: (cb: (data: { projectId: string }) => void) => () => void
      extractArchives: () => Promise<{ started: boolean }>
      onArchivesProgress: (cb: (data: { current: number; total: number; name: string }) => void) => () => void
      onArchivesDone: (cb: (data: { extracted: number; total: number }) => void) => () => void
    }
  }

  interface ProjectInfo {
    id: string
    name: string
    year?: string
    month?: string
    path: string
    createdAt: string
    lastOpenedAt: string
    status: 'active' | 'downloading' | 'uploading' | 'incloud' | 'archive' | 'ready'
    folderPath?: string
    sizeBytes?: number
    footageUrls: string[]
    downloadProgress: Record<string, number>
  }

  interface FolderEntry {
    name: string
    path: string
    type: 'file' | 'folder'
    sizeBytes?: number
    children?: FolderEntry[]
  }

  interface AppSettings {
    projectsFolder: string
    downloadsFolder: string
    dropfxLibrary: string
    davinciPath: string
    autoArchiveDays: number
    autoImportPatterns: string[]
    icloudPath: string
  }

  interface DownloadProgressData {
    projectId: string
    fileUrl: string
    percent: number
    fileName: string
  }

  interface DaVinciOpenResult {
    launched: boolean
    projectReady: boolean
    message?: string
    drpFilePath?: string
    project: ProjectInfo
  }

  interface ArchiveProgressInfo {
    current: number
    total: number
    name?: string
  }

}
