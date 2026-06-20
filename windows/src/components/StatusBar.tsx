import React from 'react'
import { useStore } from '../store/useStore'

export default function StatusBar() {
  const { activeProjectId, projects, icloudSyncing } = useStore()

  const activeProject = projects.find((p) => p.id === activeProjectId)

  return (
    <div style={{
      height: 32,
      background: 'var(--bg)',
      borderTop: '1px solid var(--sep)',
      display: 'flex',
      alignItems: 'center',
      padding: '0 16px',
      gap: 16,
      flexShrink: 0,
    }}>
      {/* Active project */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        gap: 6,
        fontSize: 12,
        color: 'var(--dim)',
      }}>
        <span>Active:</span>
        {activeProject ? (
          <span style={{ color: 'var(--txt)', fontWeight: 500 }}>
            {activeProject.name}
          </span>
        ) : (
          <span style={{ color: 'var(--dim)' }}>None</span>
        )}
        {activeProject && (
          <span style={{
            display: 'inline-block',
            width: 6,
            height: 6,
            borderRadius: '50%',
            background: 'var(--good)',
            animation: 'pulse-dot 2s infinite',
            marginLeft: 2,
          }} />
        )}
      </div>

      <div style={{
        width: 1,
        height: 14,
        background: 'var(--sep)',
      }} />

      {/* iCloud status */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        gap: 5,
        fontSize: 12,
        color: 'var(--dim)',
      }}>
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round">
          <path d="M9.5 8.5H8.5A3 3 0 0 1 5.5 5.5a2.5 2.5 0 0 1 4.95-.5H10a2 2 0 0 1 0 4z" />
          <path d="M3 8.5a2 2 0 0 1-.5-3.93A3 3 0 0 1 8 6" />
        </svg>
        <span>
          iCloud:{' '}
          <span style={{ color: icloudSyncing ? 'var(--warn)' : 'var(--good)' }}>
            {icloudSyncing ? 'syncing' : 'ready'}
          </span>
        </span>
        {icloudSyncing && (
          <span style={{
            display: 'inline-block',
            width: 10,
            height: 10,
            border: '1.5px solid var(--warn)',
            borderTopColor: 'transparent',
            borderRadius: '50%',
            animation: 'spin 0.8s linear infinite',
          }} />
        )}
      </div>

      {/* Spacer */}
      <div style={{ flex: 1 }} />

      {/* Version */}
      <span style={{ fontSize: 11, color: 'var(--dim)', opacity: 0.5 }}>
        v1.0.0
      </span>
    </div>
  )
}
