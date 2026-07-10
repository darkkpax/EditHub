import React, { useState, useEffect, useRef, useCallback } from 'react'
import { useStore } from '../store/useStore'
import { IconSearch, IconWaveform, IconPlay, IconPause } from '../components/icons/icons'
import { WindowControls } from '../components/TitleBar'

const BACKEND = 'http://127.0.0.1:8765'

interface AssetInfo {
  id: string
  name: string
  path: string
  duration: number
  tags: string[]
  waveform?: number[]
}

// ── Waveform mini-viz ────────────────────────────────────────────────────────

function WaveformBar({ data, playing }: { data?: number[]; playing: boolean }) {
  const bars = data || Array.from({ length: 40 }, (_, i) => 0.3 + 0.6 * Math.abs(Math.sin(i * 0.5)))

  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      gap: 1.5,
      height: 28,
      overflow: 'hidden',
    }}>
      {bars.map((v, i) => (
        <div
          key={i}
          style={{
            width: 2,
            height: `${Math.max(15, v * 100)}%`,
            background: playing ? 'var(--accent)' : 'var(--dim)',
            borderRadius: 1,
            opacity: playing ? 1 : 0.5,
            transition: 'background 0.2s ease, opacity 0.2s ease',
            animation: playing ? `bob-bar 0.6s ${i * 0.04}s infinite alternate ease-in-out` : 'none',
          }}
        />
      ))}
    </div>
  )
}

// ── Asset card ───────────────────────────────────────────────────────────────

function AssetCard({ asset }: { asset: AssetInfo }) {
  const { activeProjectId, projects, addToast } = useStore()
  const [playing, setPlaying] = useState(false)
  const [waveform, setWaveform] = useState<number[] | undefined>(undefined)
  const audioRef = useRef<HTMLAudioElement | null>(null)
  const cardRef = useRef<HTMLDivElement>(null)

  // Load waveform lazily
  useEffect(() => {
    fetch(`${BACKEND}/assets/${asset.id}/waveform`)
      .then((r) => r.json())
      .then((data) => setWaveform(data.waveform || data))
      .catch(() => {})
  }, [asset.id])

  const togglePlay = (e: React.MouseEvent) => {
    e.stopPropagation()
    if (!audioRef.current) {
      audioRef.current = new Audio(`${BACKEND}/assets/${asset.id}/audio`)
    }
    if (playing) {
      audioRef.current.pause()
      setPlaying(false)
    } else {
      audioRef.current.play().then(() => setPlaying(true)).catch(() => {})
      audioRef.current.onended = () => setPlaying(false)
    }
  }

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      audioRef.current?.pause()
    }
  }, [])

  const handleDragStart = (e: React.DragEvent) => {
    // Put the file path in dataTransfer so DaVinci (or any app) can receive it
    e.dataTransfer.setData('text/plain', asset.path)
    e.dataTransfer.setData('DownloadURL', `audio/${asset.name}:${asset.path}`)
    e.dataTransfer.effectAllowed = 'copy'

    // Immediately copy to active project's SFX folder so the file is there
    const activeProject = projects.find((p) => p.id === activeProjectId)
    if (activeProject?.folderPath) {
      fetch(`${BACKEND}/assets/${asset.id}/copy`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          dest: `${activeProject.folderPath}/SFX/${asset.name}`,
        }),
      })
        .then((r) => r.ok && addToast({ type: 'success', message: `${asset.name} → SFX/` }))
        .catch(() => {})
    }
  }

  const formatDuration = (secs: number): string => {
    const m = Math.floor(secs / 60)
    const s = Math.floor(secs % 60)
    return `${m}:${s.toString().padStart(2, '0')}`
  }

  return (
    <div
      ref={cardRef}
      className="card"
      draggable
      onDragStart={handleDragStart}
      style={{
        padding: '10px 12px',
        cursor: 'grab',
        border: '1px solid var(--sep)',
        display: 'flex',
        flexDirection: 'column',
        gap: 8,
        userSelect: 'none',
      }}
      onMouseEnter={() => {
        if (!playing && audioRef.current) {
          // Don't auto-play, let user click
        }
      }}
    >
      {/* Name + duration row */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <button
          onClick={togglePlay}
          style={{
            width: 28,
            height: 28,
            borderRadius: 8,
            background: playing ? 'var(--accent)' : 'rgba(255,255,255,0.08)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexShrink: 0,
          }}
        >
          {playing ? (
            <IconPause size={12} color="#fff" />
          ) : (
            <IconPlay size={12} color={playing ? '#fff' : 'var(--dim)'} />
          )}
        </button>

        <div style={{ flex: 1, minWidth: 0 }}>
          <p style={{
            fontSize: 12,
            fontWeight: 500,
            color: 'var(--txt)',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
          }}>
            {asset.name}
          </p>
          <p style={{ fontSize: 10, color: 'var(--dim)', marginTop: 1 }}>
            {formatDuration(asset.duration)}
          </p>
        </div>
      </div>

      {/* Waveform */}
      <WaveformBar data={waveform} playing={playing} />

      {/* Tags */}
      {asset.tags.length > 0 && (
        <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
          {asset.tags.slice(0, 3).map((tag) => (
            <span key={tag} style={{
              fontSize: 10,
              padding: '2px 6px',
              borderRadius: 20,
              background: 'rgba(109,109,240,0.15)',
              color: 'var(--brand)',
              border: '1px solid rgba(109,109,240,0.2)',
            }}>
              {tag}
            </span>
          ))}
        </div>
      )}
    </div>
  )
}

// ── Folder tree item ─────────────────────────────────────────────────────────

interface FolderNode {
  name: string
  path: string
  children: FolderNode[]
}

function FolderTreeItem({
  node,
  selected,
  onSelect,
  depth = 0,
}: {
  node: FolderNode
  selected: string
  onSelect: (path: string) => void
  depth?: number
}) {
  const [expanded, setExpanded] = useState(depth === 0)
  const isSelected = node.path === selected

  return (
    <div>
      <button
        onClick={() => {
          onSelect(node.path)
          if (node.children.length > 0) setExpanded((v) => !v)
        }}
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 6,
          width: '100%',
          padding: `5px 8px 5px ${8 + depth * 14}px`,
          borderRadius: 8,
          fontSize: 13,
          color: isSelected ? 'var(--accent)' : 'var(--txt)',
          background: isSelected ? 'rgba(47,140,255,0.1)' : 'transparent',
          textAlign: 'left',
        }}
      >
        {node.children.length > 0 && (
          <svg
            width="10"
            height="10"
            viewBox="0 0 10 10"
            fill="none"
            stroke="var(--dim)"
            strokeWidth="1.5"
            style={{
              transform: expanded ? 'rotate(90deg)' : 'rotate(0deg)',
              transition: 'transform 0.2s var(--ease-spring)',
              flexShrink: 0,
            }}
          >
            <path d="M3 2l4 3-4 3" />
          </svg>
        )}
        {node.children.length === 0 && (
          <span style={{ width: 10, display: 'inline-block', flexShrink: 0 }} />
        )}
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={isSelected ? 'var(--accent)' : 'var(--dim)'} strokeWidth="1.3" strokeLinecap="round">
          <path d="M1 4a1.5 1.5 0 0 1 1.5-1.5H5l1.5 1.5H11A1.5 1.5 0 0 1 12.5 5.5v5A1.5 1.5 0 0 1 11 12H2.5A1.5 1.5 0 0 1 1 10.5V4z" />
        </svg>
        <span style={{
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          whiteSpace: 'nowrap',
        }}>
          {node.name}
        </span>
      </button>

      {expanded && node.children.map((child) => (
        <FolderTreeItem
          key={child.path}
          node={child}
          selected={selected}
          onSelect={onSelect}
          depth={depth + 1}
        />
      ))}
    </div>
  )
}

// ── DropFX screen ────────────────────────────────────────────────────────────

export default function DropFX() {
  const { dropfxAvailable, addToast, activeProjectId, projects, settings, setSettings } = useStore()
  const activeProject = projects.find((p) => p.id === activeProjectId)
  const [assets, setAssets] = useState<AssetInfo[]>([])
  const [folders, setFolders] = useState<FolderNode[]>([])
  const [selectedFolder, setSelectedFolder] = useState('')
  const [search, setSearch] = useState('')
  const [selectedTags, setSelectedTags] = useState<string[]>([])
  const [loading, setLoading] = useState(false)

  const chooseLibrary = async () => {
    const picked = await window.edithub.pickFolder()
    if (!picked) return
    const next = { ...(settings as any), dropfxLibrary: picked }
    await window.edithub.setSettings(next)
    setSettings(next)
    addToast({ type: 'success', message: 'DropFX library saved. Restart EditHub to re-index it.' })
  }

  // Fetch assets
  const loadAssets = useCallback(async () => {
    if (!dropfxAvailable) return
    setLoading(true)
    try {
      const params = new URLSearchParams()
      if (search) params.set('q', search)
      if (selectedFolder) params.set('folder', selectedFolder)
      if (selectedTags.length) params.set('tags', selectedTags.join(','))

      const res = await fetch(`${BACKEND}/assets?${params}`)
      const data = await res.json()
      setAssets(Array.isArray(data) ? data : data.assets || [])
    } catch {
      setAssets([])
    } finally {
      setLoading(false)
    }
  }, [dropfxAvailable, search, selectedFolder, selectedTags])

  // Fetch folder tree
  const loadFolders = useCallback(async () => {
    if (!dropfxAvailable) return
    try {
      const res = await fetch(`${BACKEND}/folders`)
      const data = await res.json()
      setFolders(Array.isArray(data) ? data : data.folders || [])
    } catch {
      setFolders([])
    }
  }, [dropfxAvailable])

  useEffect(() => {
    loadFolders()
  }, [loadFolders])

  useEffect(() => {
    const timer = setTimeout(loadAssets, 200)
    return () => clearTimeout(timer)
  }, [loadAssets])

  // Collect all unique tags from assets
  const allTags = Array.from(new Set(assets.flatMap((a) => a.tags))).slice(0, 20)

  const toggleTag = (tag: string) => {
    setSelectedTags((prev) =>
      prev.includes(tag) ? prev.filter((t) => t !== tag) : [...prev, tag]
    )
  }

  if (!dropfxAvailable) {
    return (
      <div style={{
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 16,
        color: 'var(--dim)',
        animation: 'fade-in 0.3s ease both',
      }}>
        <div style={{
          width: 56,
          height: 56,
          borderRadius: 16,
          background: 'var(--card)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}>
          <svg width="28" height="28" viewBox="0 0 28 28" fill="none" stroke="var(--dim)" strokeWidth="1.5" strokeLinecap="round">
            <path d="M4 20 Q7 10 14 14 Q21 18 24 8" />
          </svg>
        </div>
        <div style={{ textAlign: 'center' }}>
          <p style={{ fontSize: 16, fontWeight: 600, color: 'var(--txt)', marginBottom: 6 }}>
            DropFX Unavailable
          </p>
          <p style={{ fontSize: 13, color: 'var(--dim)', maxWidth: 280, lineHeight: 1.5 }}>
            The Python backend isn't running. Make sure Python is installed and the backend script is present.
          </p>
        </div>
        <button
          className="btn btn-secondary"
          onClick={() => {
            fetch(`${BACKEND}/health`)
              .then(() => window.location.reload())
              .catch(() => addToast({ type: 'error', message: 'Backend still unavailable' }))
          }}
        >
          Retry Connection
        </button>
      </div>
    )
  }

  return (
    <div style={{
      height: '100%',
      display: 'flex',
      overflow: 'hidden',
    }}>
      {/* Sidebar: library, search, filters */}
      <div style={{
        width: 315,
        minWidth: 280,
        borderRight: '1px solid var(--sep)',
        background: 'rgba(255,255,255,0.025)',
        overflowY: 'auto',
        padding: '12px 12px 90px',
        flexShrink: 0,
      }}>
        <div style={{ height: 16 }} />
        <div style={{ position: 'relative', marginBottom: 12 }}>
          <svg width="15" height="15" viewBox="0 0 15 15" fill="none" stroke="var(--dim)" strokeWidth="1.5" strokeLinecap="round"
            style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)', pointerEvents: 'none' }}>
            <circle cx="6" cy="6" r="4.5" />
            <path d="M10 10l2.5 2.5" />
          </svg>
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search sounds"
            style={{ paddingLeft: 36, height: 38, borderRadius: 999 }}
          />
        </div>
        <div style={{
          border: '1px solid var(--sep)',
          borderRadius: 13,
          background: 'rgba(255,255,255,0.045)',
          padding: 12,
          marginBottom: 14,
        }}>
          <div style={{ color: 'var(--dim)', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: 6 }}>
            Active Project
          </div>
          {activeProject ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--good)', display: 'inline-block', animation: 'pulse-dot 2s infinite' }} />
              <strong style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{activeProject.name}</strong>
            </div>
          ) : (
            <div style={{ color: 'var(--warn)', fontSize: 13, lineHeight: 1.4 }}>
              Open a project in EditHub to copy sounds into SFX.
            </div>
          )}
        </div>

        <div style={{
          border: '1px solid var(--sep)',
          borderRadius: 13,
          background: 'rgba(255,255,255,0.045)',
          padding: 12,
          marginBottom: 14,
        }}>
          <div style={{ color: 'var(--dim)', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: 6 }}>
            DropFX Settings
          </div>
          <div style={{ color: 'var(--dim)', fontSize: 12, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', marginBottom: 8 }}>
            {settings?.dropfxLibrary || 'Library not selected'}
          </div>
          <button className="btn btn-secondary" onClick={chooseLibrary} style={{ fontSize: 12, padding: '6px 10px' }}>
            Choose Sound Library
          </button>
        </div>
        <p style={{
          fontSize: 11,
          color: 'var(--dim)',
          textTransform: 'uppercase',
          letterSpacing: '0.06em',
          padding: '0 8px',
          marginBottom: 6,
        }}>
          Library
        </p>

        {/* All assets option */}
        <button
          onClick={() => setSelectedFolder('')}
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 6,
            width: '100%',
            padding: '5px 8px',
            borderRadius: 8,
            fontSize: 13,
            color: selectedFolder === '' ? 'var(--accent)' : 'var(--txt)',
            background: selectedFolder === '' ? 'rgba(47,140,255,0.1)' : 'transparent',
            textAlign: 'left',
            marginBottom: 4,
          }}
        >
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round">
            <rect x="1" y="1" width="5" height="5" rx="1" />
            <rect x="8" y="1" width="5" height="5" rx="1" />
            <rect x="1" y="8" width="5" height="5" rx="1" />
            <rect x="8" y="8" width="5" height="5" rx="1" />
          </svg>
          All Assets
        </button>

        {folders.map((node) => (
          <FolderTreeItem
            key={node.path}
            node={node}
            selected={selectedFolder}
            onSelect={setSelectedFolder}
          />
        ))}

        {allTags.length > 0 && (
          <>
            <p style={{
              fontSize: 11,
              color: 'var(--dim)',
              textTransform: 'uppercase',
              letterSpacing: '0.06em',
              padding: '16px 8px 6px',
            }}>
              Tags
            </p>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', padding: '0 4px' }}>
              {allTags.map((tag) => {
                const active = selectedTags.includes(tag)
                return (
                  <button
                    key={tag}
                    onClick={() => toggleTag(tag)}
                    style={{
                      fontSize: 11,
                      padding: '4px 9px',
                      borderRadius: 999,
                      border: `1px solid ${active ? 'var(--accent)' : 'var(--sep)'}`,
                      background: active ? 'rgba(47,140,255,0.15)' : 'rgba(255,255,255,0.035)',
                      color: active ? 'var(--accent)' : 'var(--dim)',
                    }}
                  >
                    {tag}
                  </button>
                )
              })}
            </div>
          </>
        )}
      </div>

      {/* Right panel */}
      <div style={{
        flex: 1,
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
      }}>
        <div style={{
          padding: '16px 18px',
          borderBottom: '1px solid var(--sep)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 16,
          flexShrink: 0,
          WebkitAppRegion: 'drag' as any,
        }}>
          <div style={{ WebkitAppRegion: 'no-drag' as any }}>
            <h2 style={{ fontSize: 20, fontWeight: 750 }}>DropFX Library</h2>
            <p style={{ color: 'var(--dim)', fontSize: 13, marginTop: 2 }}>
              {selectedFolder || 'All sounds'} · {assets.length} sound{assets.length === 1 ? '' : 's'}
            </p>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, WebkitAppRegion: 'no-drag' as any }}>
            <div style={{
              padding: '8px 11px',
              border: '1px solid var(--sep)',
              borderRadius: 999,
              color: activeProject ? 'var(--good)' : 'var(--warn)',
              background: 'rgba(255,255,255,0.04)',
              fontSize: 12,
              fontWeight: 650,
            }}>
              {activeProject ? 'Linked to EditHub' : 'No active project'}
            </div>
            <WindowControls />
          </div>
        </div>

        {/* Active project indicator */}
        {activeProject ? (
          <div style={{
            padding: '6px 12px',
            borderBottom: '1px solid var(--sep)',
            display: 'flex',
            alignItems: 'center',
            gap: 6,
            fontSize: 12,
            color: 'var(--dim)',
            flexShrink: 0,
          }}>
            <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--good)', display: 'inline-block', animation: 'pulse-dot 2s infinite' }} />
            Drag to copy into <strong style={{ color: 'var(--txt)' }}>{activeProject.name}</strong>/SFX
          </div>
        ) : (
          <div style={{ padding: '6px 12px', borderBottom: '1px solid var(--sep)', fontSize: 12, color: 'var(--warn)', flexShrink: 0 }}>
            Open a project first to copy sounds automatically
          </div>
        )}

        {/* Search + tags bar */}
        <div style={{
          display: 'none',
          padding: '10px 12px',
          borderBottom: '1px solid var(--sep)',
          flexDirection: 'column',
          gap: 8,
          flexShrink: 0,
        }}>
          <div style={{ position: 'relative' }}>
            <svg
              width="15"
              height="15"
              viewBox="0 0 15 15"
              fill="none"
              stroke="var(--dim)"
              strokeWidth="1.5"
              strokeLinecap="round"
              style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', pointerEvents: 'none' }}
            >
              <circle cx="6" cy="6" r="4.5" />
              <path d="M10 10l2.5 2.5" />
            </svg>
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search sounds…"
              style={{ paddingLeft: 32 }}
            />
          </div>

          {allTags.length > 0 && (
            <div style={{
              display: 'flex',
              gap: 6,
              flexWrap: 'wrap',
            }}>
              {allTags.map((tag) => {
                const active = selectedTags.includes(tag)
                return (
                  <button
                    key={tag}
                    onClick={() => toggleTag(tag)}
                    style={{
                      fontSize: 11,
                      padding: '3px 8px',
                      borderRadius: 20,
                      border: `1px solid ${active ? 'var(--brand)' : 'var(--sep)'}`,
                      background: active ? 'rgba(109,109,240,0.15)' : 'transparent',
                      color: active ? 'var(--brand)' : 'var(--dim)',
                      transition: 'all 0.15s ease',
                    }}
                  >
                    {tag}
                  </button>
                )
              })}
            </div>
          )}
        </div>

        {/* Asset grid */}
        <div style={{
          flex: 1,
          overflow: 'auto',
          padding: 18,
        }}>
          {loading ? (
            <div style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              height: '100%',
              gap: 10,
              color: 'var(--dim)',
            }}>
              <span style={{
                width: 18,
                height: 18,
                border: '2px solid var(--sep)',
                borderTopColor: 'var(--accent)',
                borderRadius: '50%',
                animation: 'spin 0.7s linear infinite',
                display: 'inline-block',
              }} />
              Loading assets…
            </div>
          ) : assets.length === 0 ? (
            <div style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              justifyContent: 'center',
              height: '100%',
              gap: 10,
              color: 'var(--dim)',
            }}>
              <svg width="40" height="40" viewBox="0 0 40 40" fill="none" stroke="var(--dim)" strokeWidth="1.5" strokeLinecap="round">
                <path d="M8 28 Q12 16 20 20 Q28 24 32 12" />
              </svg>
              <p style={{ fontSize: 14 }}>No sounds found</p>
            </div>
          ) : (
            <div style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fill, minmax(210px, 1fr))',
              gap: 12,
            }}>
              {assets.map((asset) => (
                <AssetCard key={asset.id} asset={asset} />
              ))}
            </div>
          )}
        </div>

        {/* Footer */}
        {assets.length > 0 && (
          <div style={{
            padding: '8px 12px',
            borderTop: '1px solid var(--sep)',
            fontSize: 12,
            color: 'var(--dim)',
            flexShrink: 0,
          }}>
            {assets.length} sound{assets.length !== 1 ? 's' : ''} • Drag to timeline or project
          </div>
        )}
      </div>
    </div>
  )
}
