import React from 'react'

export default function TitleBar() {
  const minimize = () => window.edithub.minimizeWindow()
  const close = () => window.edithub.closeWindow()

  return (
    <div style={{
      height: 40,
      background: 'var(--bg)',
      borderBottom: '1px solid var(--sep)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      paddingLeft: 16,
      paddingRight: 8,
      WebkitAppRegion: 'drag' as any,
      flexShrink: 0,
    }}>
      {/* App title */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        gap: 8,
      }}>
        <div style={{
          width: 20,
          height: 20,
          borderRadius: '50%',
          background: 'var(--brand-grad)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: 11,
          fontWeight: 700,
          color: '#fff',
          flexShrink: 0,
        }}>
          E
        </div>
        <span style={{
          fontSize: 13,
          fontWeight: 600,
          color: 'var(--txt)',
          letterSpacing: '-0.01em',
        }}>
          EditHub
        </span>
      </div>

      {/* Window controls */}
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
          title="Close to tray"
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
    </div>
  )
}
