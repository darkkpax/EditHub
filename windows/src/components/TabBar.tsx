import React, { useRef, useState, useLayoutEffect } from 'react'
import { useStore, TabId } from '../store/useStore'
import { WindowControls } from './TitleBar'

interface Tab {
  id: TabId
  label: string
  icon: React.ReactNode
}

const tabs: Tab[] = [
  {
    id: 'projects',
    label: 'Projects',
    icon: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <rect x="2" y="2" width="5" height="5" rx="1.5" />
        <rect x="9" y="2" width="5" height="5" rx="1.5" />
        <rect x="2" y="9" width="5" height="5" rx="1.5" />
        <rect x="9" y="9" width="5" height="5" rx="1.5" />
      </svg>
    ),
  },
  {
    id: 'settings',
    label: 'Settings',
    icon: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
        <circle cx="8" cy="8" r="2" />
        <path d="M8 1v2M8 13v2M1 8h2M13 8h2M3.05 3.05l1.41 1.41M11.54 11.54l1.41 1.41M3.05 12.95l1.41-1.41M11.54 4.46l1.41-1.41" />
      </svg>
    ),
  },
]

const CIRC = 2 * Math.PI * 13

function CloudIcon({ spinning = false }: { spinning?: boolean }) {
  return (
    <svg width="17" height="17" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M13.5 12.5H12A4 4 0 0 1 8 8.5a3.5 3.5 0 0 1 6.94-.7H15a2.5 2.5 0 0 1 0 5z" />
      <path d="M4 12.5A3 3 0 0 1 3.5 6.6 4.5 4.5 0 0 1 12 8" />
      {spinning ? (
        <path d="M9 14v-3M7.5 12.5l1.5 1.5 1.5-1.5" style={{ animation: 'soft-bob 1.1s var(--ease-spring) infinite' }} />
      ) : (
        <path d="M6.5 11l1.6 1.6 3.2-3.7" />
      )}
    </svg>
  )
}

export default function TabBar() {
  const { activeTab, setActiveTab, icloudSyncing, archivesProgress } = useStore()
  const tabRefs = useRef<(HTMLButtonElement | null)[]>([])
  const [pillStyle, setPillStyle] = useState({ left: 0, width: 0 })
  const [cloudOpen, setCloudOpen] = useState(false)

  useLayoutEffect(() => {
    const idx = tabs.findIndex((t) => t.id === activeTab)
    const el = tabRefs.current[idx]
    if (el) {
      const parent = el.parentElement!
      const parentRect = parent.getBoundingClientRect()
      const rect = el.getBoundingClientRect()
      setPillStyle({ left: rect.left - parentRect.left, width: rect.width })
    }
  }, [activeTab])

  const extractPct = archivesProgress && archivesProgress.total > 0
    ? archivesProgress.current / archivesProgress.total
    : 0
  const cloudBusy = Boolean(archivesProgress || icloudSyncing)
  const cloudColor = archivesProgress ? 'var(--accent)' : icloudSyncing ? 'var(--warn)' : 'var(--good)'
  const cloudTitle = archivesProgress
    ? 'Restoring from iCloud'
    : icloudSyncing ? 'iCloud is syncing' : 'iCloud is ready'
  const cloudDetail = archivesProgress?.name
    ? archivesProgress.name.replace(/^__extracting_/i, '').replace(/_\d{10,}.*$/i, '').replace(/_/g, ' ')
    : archivesProgress ? 'Preparing project files' : icloudSyncing ? 'Uploading and downloading changes' : 'All project archives are settled'

  return (
    <div style={{
      height: 44,
      background: 'rgba(28,28,30,0.72)',
      backdropFilter: 'blur(18px) saturate(1.2)',
      WebkitBackdropFilter: 'blur(18px) saturate(1.2)',
      borderBottom: '1px solid var(--sep)',
      display: 'flex',
      alignItems: 'center',
      padding: '0 8px',
      position: 'relative',
      flexShrink: 0,
      WebkitAppRegion: 'drag' as any,
    }}>
      <div style={{
        position: 'absolute',
        top: 6, height: 32, borderRadius: 10,
        background: 'var(--card)',
        boxShadow: '0 1px 4px rgba(0,0,0,0.3)',
        transition: 'left 0.34s var(--ease-spring), width 0.34s var(--ease-spring)',
        left: pillStyle.left, width: pillStyle.width,
        pointerEvents: 'none', zIndex: 0,
      }} />

      {tabs.map((tab, i) => {
        const isActive = tab.id === activeTab
        return (
          <button
            key={tab.id}
            ref={(el) => { tabRefs.current[i] = el }}
            onClick={() => setActiveTab(tab.id)}
            style={{
              position: 'relative', zIndex: 1,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              padding: 0, width: 38, height: 32, borderRadius: 10,
              color: isActive ? 'var(--txt)' : 'var(--dim)',
              transition: 'color 0.2s ease, opacity 0.2s ease, transform 0.2s var(--ease-spring)',
              background: 'transparent',
              WebkitAppRegion: 'no-drag' as any,
              opacity: isActive ? 1 : 0.65,
            }}
            title={tab.label}
          >
            {tab.icon}
          </button>
        )
      })}

      <div
        onMouseEnter={() => setCloudOpen(true)}
        onMouseLeave={() => setCloudOpen(false)}
        style={{
          position: 'relative',
          zIndex: 3,
          width: 42,
          height: 34,
          display: 'grid',
          placeItems: 'center',
          color: cloudColor,
          opacity: cloudBusy ? 1 : 0.78,
          WebkitAppRegion: 'no-drag' as any,
        }}
      >
        {archivesProgress && (
          <svg width="38" height="32" viewBox="0 0 38 32" style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
            <circle cx="19" cy="16" r="13" fill="none" stroke="rgba(47,140,255,0.15)" strokeWidth="2" />
            <circle
              cx="19" cy="16" r="13"
              fill="none"
              stroke="var(--accent)"
              strokeWidth="2"
              strokeLinecap="round"
              strokeDasharray={CIRC}
              strokeDashoffset={CIRC * (1 - extractPct)}
              style={{ transform: 'rotate(-90deg)', transformOrigin: '19px 16px', transition: 'stroke-dashoffset 0.45s var(--ease-spring)' }}
            />
          </svg>
        )}
        <CloudIcon spinning={cloudBusy} />
        {cloudBusy && (
          <span style={{
            position: 'absolute',
            right: 5,
            top: 6,
            width: 6,
            height: 6,
            borderRadius: '50%',
            background: cloudColor,
            boxShadow: `0 0 0 5px ${archivesProgress ? 'rgba(47,140,255,0.14)' : 'rgba(255,159,10,0.14)'}`,
            animation: 'pulse-dot 1.5s infinite',
          }} />
        )}

        {cloudOpen && (
          <div style={{
            position: 'absolute',
            top: 38,
            left: -8,
            width: 286,
            padding: 14,
            borderRadius: 14,
            background: 'rgba(35,35,38,0.52)',
            border: '1px solid rgba(255,255,255,0.14)',
            boxShadow: '0 22px 70px rgba(0,0,0,0.48)',
            backdropFilter: 'blur(13px) saturate(1.18)',
            WebkitBackdropFilter: 'blur(13px) saturate(1.18)',
            animation: 'popover-in 0.28s var(--ease-spring) both',
            color: 'var(--txt)',
            pointerEvents: 'none',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
              <div style={{
                width: 38, height: 38, borderRadius: 10,
                display: 'grid', placeItems: 'center',
                background: archivesProgress ? 'rgba(47,140,255,0.16)' : icloudSyncing ? 'rgba(255,159,10,0.15)' : 'rgba(52,199,89,0.14)',
                color: cloudColor,
                boxShadow: 'inset 0 0 0 1px rgba(255,255,255,0.08)',
              }}>
                <CloudIcon spinning={cloudBusy} />
              </div>
              <div style={{ minWidth: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 750 }}>{cloudTitle}</div>
                <div style={{ color: 'var(--dim)', fontSize: 11, marginTop: 2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 210 }}>
                  {cloudDetail}
                </div>
              </div>
            </div>

            {archivesProgress ? (
              <div style={{ marginTop: 13 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, color: 'var(--dim)', marginBottom: 6 }}>
                  <span>{archivesProgress.current} of {archivesProgress.total}</span>
                  <span>{Math.round(extractPct * 100)}%</span>
                </div>
                <div style={{ height: 7, borderRadius: 999, background: 'rgba(255,255,255,0.09)', overflow: 'hidden' }}>
                  <div style={{
                    width: `${Math.max(4, extractPct * 100)}%`,
                    height: '100%',
                    borderRadius: 999,
                    background: 'linear-gradient(90deg, #2f8cff, #7ab8ff)',
                    transition: 'width 0.45s var(--ease-spring)',
                  }} />
                </div>
              </div>
            ) : (
              <div style={{ marginTop: 12, color: 'var(--dim)', fontSize: 11 }}>
                {icloudSyncing ? 'Keeping archive files in sync without blocking the workspace.' : 'Hover here any time to check cloud work.'}
              </div>
            )}
          </div>
        )}
      </div>

      <div style={{ flex: 1, height: '100%', WebkitAppRegion: 'drag' as any }} />
      <WindowControls />
    </div>
  )
}
