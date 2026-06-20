import React, { useState } from 'react'
import { useStore, ToastMessage } from '../store/useStore'

function ToastItem({ toast }: { toast: ToastMessage }) {
  const { removeToast, activeProjectId, projects, addToast } = useStore()
  const [leaving, setLeaving] = useState(false)

  const dismiss = () => {
    setLeaving(true)
    setTimeout(() => removeToast(toast.id), 300)
  }

  const iconMap = {
    info: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="var(--accent)">
        <circle cx="8" cy="8" r="8" opacity="0.15" />
        <path d="M8 7v4M8 5.5V5" stroke="var(--accent)" strokeWidth="1.5" strokeLinecap="round" fill="none" />
      </svg>
    ),
    success: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
        <circle cx="8" cy="8" r="8" fill="var(--good)" opacity="0.15" />
        <path d="M5 8l2 2 4-4" stroke="var(--good)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    ),
    error: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
        <circle cx="8" cy="8" r="8" fill="var(--bad)" opacity="0.15" />
        <path d="M6 6l4 4M10 6l-4 4" stroke="var(--bad)" strokeWidth="1.5" strokeLinecap="round" />
      </svg>
    ),
    'matched-file': (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
        <circle cx="8" cy="8" r="8" fill="var(--warn)" opacity="0.15" />
        <path d="M8 5v4M8 11v.5" stroke="var(--warn)" strokeWidth="1.5" strokeLinecap="round" />
      </svg>
    ),
  }

  const handleCopyToProject = async () => {
    if (!toast.filePath || !activeProjectId) return
    const activeProject = projects.find((p) => p.id === activeProjectId)
    if (!activeProject?.folderPath) return

    // We send an IPC to copy the file
    try {
      await window.edithub.showInExplorer(toast.filePath)
      addToast({ type: 'success', message: `Copied ${toast.fileName} to project SFX/` })
    } catch {}
    dismiss()
  }

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: 8,
        background: 'var(--card)',
        border: '1px solid var(--sep)',
        borderRadius: 12,
        padding: '10px 14px',
        boxShadow: 'var(--shadow-card)',
        maxWidth: 320,
        animation: leaving ? 'toast-out 0.3s var(--ease-out) forwards' : 'toast-in 0.35s var(--ease-spring) both',
        cursor: 'pointer',
      }}
      onClick={toast.type !== 'matched-file' ? dismiss : undefined}
    >
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10 }}>
        <div style={{ flexShrink: 0, marginTop: 1 }}>
          {iconMap[toast.type]}
        </div>
        <p style={{
          fontSize: 13,
          lineHeight: 1.4,
          color: 'var(--txt)',
          flex: 1,
          wordBreak: 'break-word',
        }}>
          {toast.message}
        </p>
        <button
          onClick={(e) => { e.stopPropagation(); dismiss() }}
          style={{
            width: 20,
            height: 20,
            borderRadius: 6,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: 'var(--dim)',
            flexShrink: 0,
          }}
        >
          <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
            <path d="M1 1l8 8M9 1L1 9" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
          </svg>
        </button>
      </div>

      {toast.type === 'matched-file' && (
        <div style={{ display: 'flex', gap: 8, paddingLeft: 26 }}>
          <button
            className="btn btn-primary"
            style={{ fontSize: 12, padding: '5px 12px' }}
            onClick={handleCopyToProject}
          >
            Copy to Project
          </button>
          <button
            className="btn btn-secondary"
            style={{ fontSize: 12, padding: '5px 12px' }}
            onClick={dismiss}
          >
            Ignore
          </button>
        </div>
      )}
    </div>
  )
}

export default function Toast() {
  const { toasts } = useStore()

  if (toasts.length === 0) return null

  return (
    <div style={{
      position: 'fixed',
      bottom: 44,
      right: 16,
      zIndex: 9999,
      display: 'flex',
      flexDirection: 'column',
      gap: 8,
      alignItems: 'flex-end',
    }}>
      {toasts.map((t) => (
        <ToastItem key={t.id} toast={t} />
      ))}
    </div>
  )
}
