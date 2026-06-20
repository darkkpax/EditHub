import React, { useRef, useState, useLayoutEffect } from 'react'
import { useStore, TabId } from '../store/useStore'

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
        <rect x="2" y="2" width="5" height="5" rx="1.5" className="ic-stroke" style={{ strokeDasharray: 22, strokeDashoffset: 22 }} />
        <rect x="9" y="2" width="5" height="5" rx="1.5" className="ic-stroke" style={{ strokeDasharray: 22, strokeDashoffset: 22 }} />
        <rect x="2" y="9" width="5" height="5" rx="1.5" className="ic-stroke" style={{ strokeDasharray: 22, strokeDashoffset: 22 }} />
        <rect x="9" y="9" width="5" height="5" rx="1.5" className="ic-stroke" style={{ strokeDasharray: 22, strokeDashoffset: 22 }} />
      </svg>
    ),
  },
  {
    id: 'dropfx',
    label: 'DropFX',
    icon: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M2 11 Q4 5 8 8 Q12 11 14 5" className="ic-stroke" style={{ strokeDasharray: 40, strokeDashoffset: 40 }} />
        <circle cx="8" cy="8" r="1.5" className="ic-spark" style={{ opacity: 0 }} fill="currentColor" stroke="none" />
      </svg>
    ),
  },
  {
    id: 'settings',
    label: 'Settings',
    icon: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
        <circle cx="8" cy="8" r="2" className="ic-stroke" style={{ strokeDasharray: 14, strokeDashoffset: 14 }} />
        <path d="M8 1v2M8 13v2M1 8h2M13 8h2M3.05 3.05l1.41 1.41M11.54 11.54l1.41 1.41M3.05 12.95l1.41-1.41M11.54 4.46l1.41-1.41"
          className="ic-stroke" style={{ strokeDasharray: 60, strokeDashoffset: 60 }} />
      </svg>
    ),
  },
]

export default function TabBar() {
  const { activeTab, setActiveTab } = useStore()
  const tabRefs = useRef<(HTMLButtonElement | null)[]>([])
  const [pillStyle, setPillStyle] = useState({ left: 0, width: 0 })

  useLayoutEffect(() => {
    const idx = tabs.findIndex((t) => t.id === activeTab)
    const el = tabRefs.current[idx]
    if (el) {
      const parent = el.parentElement!
      const parentRect = parent.getBoundingClientRect()
      const rect = el.getBoundingClientRect()
      setPillStyle({
        left: rect.left - parentRect.left,
        width: rect.width,
      })
    }
  }, [activeTab])

  return (
    <div style={{
      height: 44,
      background: 'var(--bg)',
      borderBottom: '1px solid var(--sep)',
      display: 'flex',
      alignItems: 'center',
      padding: '0 12px',
      position: 'relative',
      flexShrink: 0,
    }}>
      {/* Sliding pill */}
      <div
        style={{
          position: 'absolute',
          top: 6,
          height: 32,
          borderRadius: 10,
          background: 'var(--card)',
          boxShadow: '0 1px 4px rgba(0,0,0,0.3)',
          transition: 'left 0.3s var(--ease-spring), width 0.3s var(--ease-spring)',
          left: pillStyle.left + 12,
          width: pillStyle.width,
          pointerEvents: 'none',
          zIndex: 0,
        }}
      />

      {tabs.map((tab, i) => {
        const isActive = tab.id === activeTab
        return (
          <button
            key={tab.id}
            ref={(el) => { tabRefs.current[i] = el }}
            onClick={() => setActiveTab(tab.id)}
            className={isActive ? 'on' : ''}
            style={{
              position: 'relative',
              zIndex: 1,
              display: 'flex',
              alignItems: 'center',
              gap: 6,
              padding: '0 14px',
              height: 32,
              borderRadius: 10,
              fontSize: 13,
              fontWeight: isActive ? 600 : 400,
              color: isActive ? 'var(--txt)' : 'var(--dim)',
              transition: 'color 0.2s ease, transform 0.18s var(--ease-spring)',
              background: 'transparent',
            }}
          >
            {tab.icon}
            {tab.label}
          </button>
        )
      })}
    </div>
  )
}
