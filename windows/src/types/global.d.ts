export {}

declare module 'react' {
  interface CSSProperties {
    WebkitAppRegion?: 'drag' | 'no-drag'
  }
}

declare global {
  interface Window {
    edithub: {
      listProjects: () => Promise<ProjectInfo[]>
      createProject: (name: string, urls: string[]) => Promise<ProjectInfo>
      openProject: (id: string) => Promise<void>
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
    }
  }

  interface ProjectInfo {
    id: string
    name: string
    path: string
    createdAt: string
    lastOpenedAt: string
    status: 'active' | 'downloading' | 'uploading' | 'icloud' | 'archive' | 'ready'
    sizeBytes: number
    footageUrls: string[]
    downloadProgress: Record<string, number>
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

}
