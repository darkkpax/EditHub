import React from 'react'
import { useStore } from '../store/useStore'

export default function StatusBar() {
  const { activeProjectId, projects } = useStore()

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

      {/* Spacer */}
      <div style={{ flex: 1 }} />

      {/* Version */}
      <span style={{ fontSize: 11, color: 'var(--dim)', opacity: 0.5 }}>
        v1.0.0
      </span>
    </div>
  )
}
