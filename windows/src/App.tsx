import React, { useEffect, useState } from 'react'
import { useStore } from './store/useStore'
import TitleBar from './components/TitleBar'
import TabBar from './components/TabBar'
import StatusBar from './components/StatusBar'
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

  const [onboarding, setOnboarding] = useState<boolean | null>(null) // null = loading

  // Load initial data and decide onboarding
  useEffect(() => {
    const api = window.edithub

    api.getSettings().then((s: any) => {
      setSettings(s as any)
      // Show onboarding if projects folder not set
      setOnboarding(!s?.projectsFolder)
    }).catch(() => {
      setOnboarding(true)
    })

    api.listProjects().then((list: any) => setProjects(list as any)).catch(() => {})

    fetch('http://localhost:8765/health')
      .then(() => setDropfxAvailable(true))
      .catch(() => setDropfxAvailable(false))
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
      window.edithub.listProjects().then((list: any) => setProjects(list as any)).catch(() => {})
    })

    const unsubError = api.onDownloadError(({ projectId, error }) => {
      clearDownloadProgress(projectId)
      addToast({ type: 'error', message: `Download error: ${error}` })
      window.edithub.listProjects().then((list: any) => setProjects(list as any)).catch(() => {})
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
      case 'dropfx':   return <DropFX />
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

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', overflow: 'hidden', background: 'var(--bg)' }}>
      <TitleBar />
      <TabBar />
      <main style={{ flex: 1, overflow: 'hidden', position: 'relative' }}>
        {renderTab()}
      </main>
      <StatusBar />
      <Toast />
    </div>
  )
}
