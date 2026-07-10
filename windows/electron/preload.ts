import { contextBridge, ipcRenderer } from 'electron'

export type IpcRenderer = typeof ipcRenderer

// Typed API exposed to renderer
const api = {
  debugLog: (level: 'INFO' | 'WARN' | 'ERROR', message: string, details?: unknown) =>
    ipcRenderer.send('debug:log', { level, message, details }),

  // Projects
  listProjects: () => ipcRenderer.invoke('projects:list'),
  listProjectFolders: (projectPath: string) =>
    ipcRenderer.invoke('projects:folders', { projectPath }),
  getProjectThumbnail: (projectPath: string) =>
    ipcRenderer.invoke('projects:thumbnail', { projectPath }),
  createProject: (name: string, urls: string[]) =>
    ipcRenderer.invoke('projects:create', { name, urls }),
  openProject: (id: string) => ipcRenderer.invoke('projects:open', { id }),
  archiveProject: (id: string) => ipcRenderer.invoke('projects:archive', { id }),
  deleteProject: (id: string) => ipcRenderer.invoke('projects:delete', { id }),
  restoreProject: (id: string) => ipcRenderer.invoke('projects:restore', { id }),
  cancelDownload: (projectId: string) =>
    ipcRenderer.invoke('downloads:cancel', { projectId }),
  extractArchives: () => ipcRenderer.invoke('projects:extractArchives'),

  // Settings
  getSettings: () => ipcRenderer.invoke('settings:get'),
  setSettings: (settings: Record<string, unknown>) =>
    ipcRenderer.invoke('settings:set', { settings }),

  // Shell
  pickFolder: () => ipcRenderer.invoke('dialog:pickFolder'),
  showInExplorer: (filePath: string) =>
    ipcRenderer.invoke('shell:showInExplorer', { path: filePath }),

  // Window controls
  minimizeWindow: () => ipcRenderer.invoke('window:minimize'),
  closeWindow: () => ipcRenderer.invoke('window:close'),

  // Event listeners (main → renderer)
  onDownloadProgress: (
    cb: (data: {
      projectId: string
      fileUrl: string
      percent: number
      fileName: string
    }) => void
  ) => {
    const handler = (_: Electron.IpcRendererEvent, data: Parameters<typeof cb>[0]) =>
      cb(data)
    ipcRenderer.on('download:progress', handler)
    return () => ipcRenderer.removeListener('download:progress', handler)
  },

  onDownloadComplete: (cb: (data: { projectId: string }) => void) => {
    const handler = (_: Electron.IpcRendererEvent, data: Parameters<typeof cb>[0]) =>
      cb(data)
    ipcRenderer.on('download:complete', handler)
    return () => ipcRenderer.removeListener('download:complete', handler)
  },

  onDownloadError: (
    cb: (data: { projectId: string; error: string }) => void
  ) => {
    const handler = (_: Electron.IpcRendererEvent, data: Parameters<typeof cb>[0]) =>
      cb(data)
    ipcRenderer.on('download:error', handler)
    return () => ipcRenderer.removeListener('download:error', handler)
  },

  onFileSorted: (
    cb: (data: { projectId: string; from: string; to: string }) => void
  ) => {
    const handler = (_: Electron.IpcRendererEvent, data: Parameters<typeof cb>[0]) =>
      cb(data)
    ipcRenderer.on('file:sorted', handler)
    return () => ipcRenderer.removeListener('file:sorted', handler)
  },

  onDownloadsMatched: (
    cb: (data: { fileName: string; filePath: string }) => void
  ) => {
    const handler = (_: Electron.IpcRendererEvent, data: Parameters<typeof cb>[0]) =>
      cb(data)
    ipcRenderer.on('downloads:matched', handler)
    return () => ipcRenderer.removeListener('downloads:matched', handler)
  },

  onICloudStatus: (cb: (data: { syncing: boolean }) => void) => {
    const handler = (_: Electron.IpcRendererEvent, data: Parameters<typeof cb>[0]) =>
      cb(data)
    ipcRenderer.on('icloud:status', handler)
    return () => ipcRenderer.removeListener('icloud:status', handler)
  },

  onActiveChanged: (cb: (data: { projectId: string }) => void) => {
    const handler = (_: Electron.IpcRendererEvent, data: Parameters<typeof cb>[0]) =>
      cb(data)
    ipcRenderer.on('active:changed', handler)
    return () => ipcRenderer.removeListener('active:changed', handler)
  },

  onArchivesProgress: (cb: (data: { current: number; total: number; name: string }) => void) => {
    const handler = (_: Electron.IpcRendererEvent, data: Parameters<typeof cb>[0]) =>
      cb(data)
    ipcRenderer.on('archives:progress', handler)
    return () => ipcRenderer.removeListener('archives:progress', handler)
  },

  onArchivesDone: (cb: (data: { extracted: number; total: number }) => void) => {
    const handler = (_: Electron.IpcRendererEvent, data: Parameters<typeof cb>[0]) =>
      cb(data)
    ipcRenderer.on('archives:done', handler)
    return () => ipcRenderer.removeListener('archives:done', handler)
  },
}

contextBridge.exposeInMainWorld('edithub', api)

window.addEventListener('error', (event) => {
  api.debugLog('ERROR', 'window.error', {
    message: event.message,
    filename: event.filename,
    lineno: event.lineno,
    colno: event.colno,
    stack: event.error instanceof Error ? event.error.stack : undefined,
  })
})

window.addEventListener('unhandledrejection', (event) => {
  api.debugLog('ERROR', 'unhandledrejection', {
    reason: event.reason instanceof Error ? event.reason.stack : event.reason,
  })
})

const originalWarn = console.warn.bind(console)
console.warn = (...args: unknown[]) => {
  api.debugLog('WARN', 'console.warn', { args })
  originalWarn(...args)
}

const originalError = console.error.bind(console)
console.error = (...args: unknown[]) => {
  api.debugLog('ERROR', 'console.error', { args })
  originalError(...args)
}

// Type declaration for renderer
declare global {
  interface Window {
    edithub: typeof api
  }
}
