import { contextBridge, ipcRenderer } from 'electron'

export type IpcRenderer = typeof ipcRenderer

// Typed API exposed to renderer
const api = {
  // Projects
  listProjects: () => ipcRenderer.invoke('projects:list'),
  createProject: (name: string, urls: string[]) =>
    ipcRenderer.invoke('projects:create', { name, urls }),
  openProject: (id: string) => ipcRenderer.invoke('projects:open', { id }),
  archiveProject: (id: string) => ipcRenderer.invoke('projects:archive', { id }),
  deleteProject: (id: string) => ipcRenderer.invoke('projects:delete', { id }),
  restoreProject: (id: string) => ipcRenderer.invoke('projects:restore', { id }),
  cancelDownload: (projectId: string) =>
    ipcRenderer.invoke('downloads:cancel', { projectId }),

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
}

contextBridge.exposeInMainWorld('edithub', api)

// Type declaration for renderer
declare global {
  interface Window {
    edithub: typeof api
  }
}
