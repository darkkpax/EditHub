import React, { useEffect, useState } from 'react'
import { useStore, Settings } from '../store/useStore'

// ── Shared components ────────────────────────────────────────────────────────

function SectionHeader({ title }: { title: string }) {
  return (
    <h3 style={{
      fontSize: 11,
      fontWeight: 600,
      color: 'var(--dim)',
      textTransform: 'uppercase',
      letterSpacing: '0.08em',
      padding: '0 4px',
      marginBottom: 4,
      marginTop: 8,
    }}>
      {title}
    </h3>
  )
}

function SettingsRow({
  label,
  hint,
  children,
}: {
  label: string
  hint?: string
  children: React.ReactNode
}) {
  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      padding: '10px 14px',
      gap: 12,
      borderBottom: '1px solid var(--sep)',
    }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <p style={{ fontSize: 14, color: 'var(--txt)', fontWeight: 500 }}>{label}</p>
        {hint && (
          <p style={{ fontSize: 12, color: 'var(--dim)', marginTop: 2 }}>{hint}</p>
        )}
      </div>
      <div style={{ flexShrink: 0 }}>
        {children}
      </div>
    </div>
  )
}

function PathPicker({
  value,
  onChange,
  placeholder,
}: {
  value: string
  onChange: (path: string) => void
  placeholder?: string
}) {
  const handlePick = async () => {
    const picked = await window.edithub.pickFolder()
    if (picked) onChange(picked)
  }

  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
      <span style={{
        fontSize: 12,
        color: value ? 'var(--dim)' : 'var(--dim)',
        maxWidth: 200,
        overflow: 'hidden',
        textOverflow: 'ellipsis',
        whiteSpace: 'nowrap',
        opacity: value ? 1 : 0.5,
      }}>
        {value || (placeholder || 'Not set')}
      </span>
      <button
        className="btn btn-secondary"
        onClick={handlePick}
        style={{ fontSize: 12, padding: '5px 12px' }}
      >
        Browse…
      </button>
    </div>
  )
}

// ── Patterns list ────────────────────────────────────────────────────────────

function PatternList({
  patterns,
  onChange,
}: {
  patterns: string[]
  onChange: (patterns: string[]) => void
}) {
  const [newPattern, setNewPattern] = useState('')

  const add = () => {
    if (!newPattern.trim()) return
    onChange([...patterns, newPattern.trim()])
    setNewPattern('')
  }

  const remove = (i: number) => {
    onChange(patterns.filter((_, idx) => idx !== i))
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      {patterns.map((p, i) => (
        <div key={i} style={{
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          background: 'rgba(255,255,255,0.04)',
          borderRadius: 8,
          padding: '5px 10px',
        }}>
          <code style={{
            flex: 1,
            fontSize: 12,
            color: 'var(--txt)',
            fontFamily: 'monospace',
          }}>
            {p}
          </code>
          <button
            onClick={() => remove(i)}
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
              <path d="M2 2l6 6M8 2L2 8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
          </button>
        </div>
      ))}

      <div style={{ display: 'flex', gap: 8 }}>
        <input
          value={newPattern}
          onChange={(e) => setNewPattern(e.target.value)}
          placeholder="*-enhanced*"
          style={{ flex: 1, fontSize: 12 }}
          onKeyDown={(e) => e.key === 'Enter' && add()}
        />
        <button
          className="btn btn-secondary"
          onClick={add}
          disabled={!newPattern.trim()}
          style={{ fontSize: 12, padding: '5px 12px' }}
        >
          Add
        </button>
      </div>
    </div>
  )
}

// ── Settings screen ──────────────────────────────────────────────────────────

export default function SettingsScreen() {
  const { settings, setSettings, addToast } = useStore()
  const [local, setLocal] = useState<Settings | null>(null)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (settings) {
      setLocal(settings)
    } else {
      window.edithub.getSettings().then((s) => {
        setSettings(s as unknown as Settings)
        setLocal(s as unknown as Settings)
      }).catch(() => {})
    }
  }, [settings])

  const updateLocal = (patch: Partial<Settings>) => {
    setLocal((prev) => prev ? { ...prev, ...patch } : null)
  }

  const save = async () => {
    if (!local) return
    setSaving(true)
    try {
      await window.edithub.setSettings(local as any)
      setSettings(local)
      addToast({ type: 'success', message: 'Settings saved' })
    } catch (err: any) {
      addToast({ type: 'error', message: `Save failed: ${err.message}` })
    } finally {
      setSaving(false)
    }
  }

  if (!local) {
    return (
      <div style={{
        height: '100%',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
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
      </div>
    )
  }

  return (
    <div style={{
      height: '100%',
      overflow: 'auto',
      padding: '16px',
      display: 'flex',
      flexDirection: 'column',
      gap: 4,
      maxWidth: 700,
    }}>
      {/* Folders */}
      <SectionHeader title="Folders" />
      <div className="card" style={{ overflow: 'hidden', border: '1px solid var(--sep)' }}>
        <SettingsRow
          label="Projects Folder"
          hint="Where project folders are stored"
        >
          <PathPicker
            value={local.projectsFolder}
            onChange={(p) => updateLocal({ projectsFolder: p })}
          />
        </SettingsRow>

        <SettingsRow
          label="Downloads Folder"
          hint="Watch this folder for enhanced files"
        >
          <PathPicker
            value={local.downloadsFolder}
            onChange={(p) => updateLocal({ downloadsFolder: p })}
          />
        </SettingsRow>

        <SettingsRow
          label="iCloud Drive Path"
          hint="Auto-detected or configured manually"
        >
          <PathPicker
            value={local.icloudPath}
            onChange={(p) => updateLocal({ icloudPath: p })}
          />
        </SettingsRow>

        <div style={{ borderBottom: 'none' }}>
          <SettingsRow
            label="DaVinci Resolve"
            hint="Path to Resolve.exe"
          >
            <PathPicker
              value={local.davinciPath}
              onChange={(p) => updateLocal({ davinciPath: p })}
              placeholder="C:\\Program Files\\Blackmagic Design\\DaVinci Resolve\\Resolve.exe"
            />
          </SettingsRow>
        </div>
      </div>

      {/* Automation */}
      <SectionHeader title="Automation" />
      <div className="card" style={{ overflow: 'hidden', border: '1px solid var(--sep)' }}>
        <SettingsRow
          label="Auto-archive after"
          hint="Projects not opened in this many days will be archived"
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <input
              type="number"
              value={local.autoArchiveDays}
              onChange={(e) => updateLocal({ autoArchiveDays: parseInt(e.target.value) || 30 })}
              min={1}
              max={365}
              style={{ width: 64, textAlign: 'center' }}
            />
            <span style={{ fontSize: 13, color: 'var(--dim)' }}>days</span>
          </div>
        </SettingsRow>

        <div style={{ padding: '12px 14px', borderTop: '1px solid var(--sep)' }}>
          <p style={{ fontSize: 14, fontWeight: 500, marginBottom: 8 }}>
            Auto-import patterns
          </p>
          <p style={{ fontSize: 12, color: 'var(--dim)', marginBottom: 10 }}>
            Files matching these glob patterns in your Downloads folder trigger a "copy to project" toast.
          </p>
          <PatternList
            patterns={local.autoImportPatterns}
            onChange={(patterns) => updateLocal({ autoImportPatterns: patterns })}
          />
        </div>
      </div>

      {/* Save button */}
      <div style={{
        display: 'flex',
        justifyContent: 'flex-end',
        marginTop: 8,
        paddingBottom: 8,
      }}>
        <button
          className="btn btn-primary"
          onClick={save}
          disabled={saving}
          style={{ opacity: saving ? 0.7 : 1 }}
        >
          {saving ? (
            <span style={{
              width: 12,
              height: 12,
              border: '2px solid rgba(255,255,255,0.3)',
              borderTopColor: '#fff',
              borderRadius: '50%',
              animation: 'spin 0.7s linear infinite',
              display: 'inline-block',
            }} />
          ) : (
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="#fff" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M2 7l4 4 6-6" />
            </svg>
          )}
          Save Settings
        </button>
      </div>
    </div>
  )
}
