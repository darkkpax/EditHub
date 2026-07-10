import React from 'react'

interface WindowControlsProps {
  closeTitle?: string
}

export function WindowControls({ closeTitle = 'Close to tray' }: WindowControlsProps) {
  const minimize = () => window.edithub.minimizeWindow()
  const close = () => window.edithub.closeWindow()

  return (
    <div style={{
      display: 'flex',
      gap: 4,
      WebkitAppRegion: 'no-drag' as any,
    }}>
        <button
          onClick={minimize}
          title="Minimize"
          style={{
            width: 28,
            height: 28,
            borderRadius: 8,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: 'var(--dim)',
            transition: 'background 0.15s ease, color 0.15s ease, transform 0.18s var(--ease-spring)',
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.background = 'rgba(255,255,255,0.08)'
            e.currentTarget.style.color = 'var(--txt)'
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.background = 'transparent'
            e.currentTarget.style.color = 'var(--dim)'
          }}
        >
          <svg width="10" height="2" viewBox="0 0 10 2" fill="currentColor">
            <rect width="10" height="2" rx="1" />
          </svg>
        </button>

        <button
          onClick={close}
          title={closeTitle}
          style={{
            width: 28,
            height: 28,
            borderRadius: 8,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: 'var(--dim)',
            transition: 'background 0.15s ease, color 0.15s ease, transform 0.18s var(--ease-spring)',
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.background = 'rgba(255,59,48,0.15)'
            e.currentTarget.style.color = 'var(--bad)'
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.background = 'transparent'
            e.currentTarget.style.color = 'var(--dim)'
          }}
        >
          <svg width="10" height="10" viewBox="0 0 10 10" fill="currentColor">
            <path d="M1 1l8 8M9 1L1 9" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" fill="none" />
          </svg>
        </button>
    </div>
  )
}

export default function TitleBar() {
  return (
    <div style={{
      height: 12,
      background: 'var(--bg)',
      WebkitAppRegion: 'drag' as any,
      flexShrink: 0,
    }} />
  )
}
