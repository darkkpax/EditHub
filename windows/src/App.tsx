import React, { useEffect, useState } from 'react'
import { useStore } from './store/useStore'
import TitleBar from './components/TitleBar'
import TabBar from './components/TabBar'
import Toast from './components/Toast'
import Projects from './screens/Projects'
import DropFX from './screens/DropFX'
import Settings from './screens/Settings'
import Onboarding from './screens/Onboarding'

export default function App() {
  const {
    activeTab,
    setProjects,
    upsertProject,
    setSettings,
    setActiveProjectId,
    setICloudSyncing,
    setDropfxAvailable,
    addToast,
    setDownloadProgress,
    clearDownloadProgress,
  } = useStore()

  const appMode = new URLSearchParams(window.location.search).get('app')
  const isDropFXApp = appMode === 'dropfx'
  const [onboarding, setOnboarding] = useState<boolean | null>(null) // null = loading
  const bootAt = performance.now()

  // Load initial data and decide onboarding
  useEffect(() => {
    const api = window.edithub
    api.debugLog?.('INFO', 'renderer boot', { appMode, isDropFXApp })

    const settingsAt = performance.now()
    api.getSettings().then((s: any) => {
      api.debugLog?.('INFO', 'getSettings done', { ms: Math.round(performance.now() - settingsAt) })
      setSettings(s as any)
      // Show onboarding if projects folder not set
      setOnboarding(!s?.projectsFolder)
    }).catch(() => {
      api.debugLog?.('WARN', 'getSettings failed', { ms: Math.round(performance.now() - settingsAt) })
      setOnboarding(true)
    })

    const projectsAt = performance.now()
    api.listProjects().then((list: any) => {
      api.debugLog?.('INFO', 'listProjects done', {
        ms: Math.round(performance.now() - projectsAt),
        count: Array.isArray(list) ? list.length : 0,
      })
      setProjects(list as any)
      const active = (list as any[]).find((p) => p.status === 'active')
      if (active?.id) setActiveProjectId(active.id)
    }).catch((err) => {
      api.debugLog?.('WARN', 'listProjects failed', {
        ms: Math.round(performance.now() - projectsAt),
        message: err?.message || String(err),
      })
    })

    const dropfxAt = performance.now()
    fetch('http://127.0.0.1:8765/health')
      .then(() => {
        api.debugLog?.('INFO', 'dropfx health ok', { ms: Math.round(performance.now() - dropfxAt) })
        setDropfxAvailable(true)
      })
      .catch(() => {
        api.debugLog?.('WARN', 'dropfx health failed', { ms: Math.round(performance.now() - dropfxAt) })
        setDropfxAvailable(false)
      })

    api.debugLog?.('INFO', 'renderer effect scheduled', { msFromBoot: Math.round(performance.now() - bootAt) })
  }, [])

  // Register IPC event listeners
  useEffect(() => {
    const api = window.edithub

    const unsubProgress = api.onDownloadProgress((data) => {
      setDownloadProgress(data.projectId, data)
      upsertProject({
        id: data.projectId,
        name: '',
        createdAt: '',
        lastOpenedAt: '',
        footageUrls: [],
        status: 'downloading',
        downloadProgress: { [data.fileUrl]: data.percent },
      })
    })

    const unsubComplete = api.onDownloadComplete(({ projectId }) => {
      clearDownloadProgress(projectId)
      addToast({ type: 'success', message: 'Download complete!' })
      window.edithub.listProjects().then((list: any) => {
        setProjects(list as any)
        const active = (list as any[]).find((p) => p.status === 'active')
        if (active?.id) setActiveProjectId(active.id)
      }).catch(() => {})
    })

    const unsubError = api.onDownloadError(({ projectId, error }) => {
      clearDownloadProgress(projectId)
      addToast({ type: 'error', message: `Download error: ${error}` })
      window.edithub.listProjects().then((list: any) => {
        setProjects(list as any)
        const active = (list as any[]).find((p) => p.status === 'active')
        if (active?.id) setActiveProjectId(active.id)
      }).catch(() => {})
    })

    const unsubFileSorted = api.onFileSorted(({ to }) => {
      const fileName = to.split(/[/\\]/).pop() || to
      addToast({ type: 'info', message: `Auto-sorted: ${fileName}` })
    })

    const unsubMatched = api.onDownloadsMatched(({ fileName, filePath }) => {
      addToast({ type: 'matched-file', message: `Enhanced file detected: ${fileName}`, fileName, filePath })
    })

    const unsubICloud = api.onICloudStatus(({ syncing }) => {
      setICloudSyncing(syncing)
    })

    const unsubActive = api.onActiveChanged(({ projectId }) => {
      setActiveProjectId(projectId)
    })

    return () => {
      unsubProgress(); unsubComplete(); unsubError()
      unsubFileSorted(); unsubMatched(); unsubICloud(); unsubActive()
    }
  }, [])

  const renderTab = () => {
    switch (activeTab) {
      case 'projects': return <Projects />
      case 'settings': return <Settings />
    }
  }

  // Still checking settings
  if (onboarding === null) {
    return (
      <div style={{ height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--bg)' }}>
        <span style={{
          width: 24, height: 24,
          border: '2.5px solid var(--sep)',
          borderTopColor: 'var(--accent)',
          borderRadius: '50%',
          animation: 'spin 0.7s linear infinite',
          display: 'inline-block',
        }} />
      </div>
    )
  }

  if (onboarding) {
    if (isDropFXApp) {
      return (
        <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', overflow: 'hidden', background: 'var(--bg)' }}>
          <main style={{ flex: 1, overflow: 'hidden', position: 'relative' }}>
            <DropFX />
          </main>
          <Toast />
        </div>
      )
    }

    return (
      <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', overflow: 'hidden', background: 'var(--bg)' }}>
        <TitleBar />
        <div style={{ flex: 1, overflow: 'hidden' }}>
          <Onboarding onDone={() => {
            setOnboarding(false)
            window.edithub.listProjects().then((list: any) => setProjects(list as any)).catch(() => {})
          }} />
        </div>
      </div>
    )
  }

  if (isDropFXApp) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', overflow: 'hidden', background: 'var(--bg)' }}>
        <main style={{ flex: 1, overflow: 'hidden', position: 'relative' }}>
          <DropFX />
        </main>
        <Toast />
      </div>
    )
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', overflow: 'hidden', background: 'var(--bg)' }}>
      <TabBar />
      <main style={{ flex: 1, overflow: 'hidden', position: 'relative' }}>
        {renderTab()}
      </main>
      <Toast />
    </div>
  )
}
