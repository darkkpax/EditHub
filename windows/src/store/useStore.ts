import { create } from 'zustand'

export type TabId = 'projects' | 'settings'

export type ProjectStatus =
  | 'active'
  | 'downloading'
  | 'uploading'
  | 'incloud'
  | 'archive'
  | 'ready'

export interface ProjectInfo {
  id: string
  name: string
  year?: string
  month?: string
  createdAt: string
  lastOpenedAt: string
  footageUrls: string[]
  status: ProjectStatus
  downloadProgress: Record<string, number>
  folderPath?: string
  sizeBytes?: number
}

export interface Settings {
  projectsFolder: string
  downloadsFolder: string
  dropfxLibrary: string
  davinciPath: string
  autoArchiveDays: number
  autoImportPatterns: string[]
  icloudPath: string
}

export interface ToastMessage {
  id: string
  type: 'info' | 'success' | 'error' | 'matched-file'
  message: string
  filePath?: string
  fileName?: string
}

export interface DebugLogger {
  debugLog?: (level: 'INFO' | 'WARN' | 'ERROR', message: string, details?: unknown) => void
}

export interface DownloadProgressInfo {
  projectId: string
  fileUrl: string
  fileName: string
  percent: number
}

interface AppState {
  // Navigation
  activeTab: TabId
  setActiveTab: (tab: TabId) => void

  // Projects
  projects: ProjectInfo[]
  setProjects: (projects: ProjectInfo[]) => void
  upsertProject: (project: ProjectInfo) => void
  removeProject: (id: string) => void

  // Active project (the one open in DaVinci)
  activeProjectId: string | null
  setActiveProjectId: (id: string | null) => void

  // Downloads
  downloadProgress: Record<string, DownloadProgressInfo>
  setDownloadProgress: (projectId: string, info: DownloadProgressInfo) => void
  clearDownloadProgress: (projectId: string) => void

  // Settings
  settings: Settings | null
  setSettings: (settings: Settings) => void

  // Toasts
  toasts: ToastMessage[]
  addToast: (toast: Omit<ToastMessage, 'id'>) => void
  removeToast: (id: string) => void

  // iCloud
  icloudSyncing: boolean
  setICloudSyncing: (syncing: boolean) => void

  // Archive extraction progress (background)
  archivesProgress: { current: number; total: number; name?: string } | null
  setArchivesProgress: (p: { current: number; total: number; name?: string } | null) => void

  // DropFX
  dropfxAvailable: boolean
  setDropfxAvailable: (available: boolean) => void
}

let toastCounter = 0

export const useStore = create<AppState>((set, get) => ({
  activeTab: 'projects',
  setActiveTab: (tab) => set({ activeTab: tab }),

  projects: [],
  setProjects: (projects) => set({ projects }),
  upsertProject: (project) =>
    set((state) => {
      const idx = state.projects.findIndex((p) => p.id === project.id)
      if (idx >= 0) {
        const updated = [...state.projects]
        updated[idx] = project
        return { projects: updated }
      }
      return { projects: [...state.projects, project] }
    }),
  removeProject: (id) =>
    set((state) => ({
      projects: state.projects.filter((p) => p.id !== id),
    })),

  activeProjectId: null,
  setActiveProjectId: (id) => set({ activeProjectId: id }),

  downloadProgress: {},
  setDownloadProgress: (projectId, info) =>
    set((state) => ({
      downloadProgress: { ...state.downloadProgress, [projectId]: info },
    })),
  clearDownloadProgress: (projectId) =>
    set((state) => {
      const next = { ...state.downloadProgress }
      delete next[projectId]
      return { downloadProgress: next }
    }),

  settings: null,
  setSettings: (settings) => set({ settings }),

  toasts: [],
  addToast: (toast) => {
    const id = `toast-${++toastCounter}`
    set((state) => ({
      toasts: [...state.toasts, { ...toast, id }],
    }))
    // Auto-remove after 5s (unless it's a matched-file toast needing action)
    if (toast.type !== 'matched-file') {
      setTimeout(() => {
        set((state) => ({
          toasts: state.toasts.filter((t) => t.id !== id),
        }))
      }, 5000)
    }
    return id
  },
  removeToast: (id) =>
    set((state) => ({
      toasts: state.toasts.filter((t) => t.id !== id),
    })),

  icloudSyncing: false,
  setICloudSyncing: (syncing) => set({ icloudSyncing: syncing }),

  archivesProgress: null,
  setArchivesProgress: (p) => set({ archivesProgress: p }),

  dropfxAvailable: false,
  setDropfxAvailable: (available) => set({ dropfxAvailable: available }),
}))
