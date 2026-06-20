import React, { useState, useEffect, useCallback } from 'react'
import { useStore, ProjectInfo, ProjectStatus } from '../store/useStore'
import {
  IconFolder,
  IconDownload,
  IconTrash,
  IconArchive,
  IconCloud,
  IconCheck,
  IconPlus,
  IconDaVinci,
} from '../components/icons/icons'

// ── Helpers ─────────────────────────────────────────────────────────────────

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`
}

function formatDate(iso: string): string {
  if (!iso) return '—'
  const d = new Date(iso)
  const now = new Date()
  const diffMs = now.getTime() - d.getTime()
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24))

  if (diffDays === 0) return 'Today'
  if (diffDays === 1) return 'Yesterday'
  if (diffDays < 7) return `${diffDays} days ago`
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

function StatusBadge({ status, progress }: { status: ProjectStatus; progress?: number }) {
  const configs: Record<ProjectStatus, { label: string; color: string; icon?: React.ReactNode }> = {
    active: {
      label: 'Active',
      color: 'var(--accent)',
      icon: (
        <span style={{
          width: 6, height: 6, borderRadius: '50%',
          background: 'var(--accent)',
          display: 'inline-block',
          animation: 'pulse-dot 2s infinite',
          flexShrink: 0,
        }} />
      ),
    },
    downloading: {
      label: progress != null ? `${progress}%` : 'Downloading',
      color: 'var(--warn)',
      icon: (
        <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
          <path d="M5 2v4M3 4l2 2 2-2" stroke="var(--warn)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M2 8h6" stroke="var(--warn)" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
      ),
    },
    uploading: {
      label: 'Uploading',
      color: 'var(--brand)',
      icon: (
        <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
          <path d="M5 8V4M3 6l2-2 2 2" stroke="var(--brand)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M2 8h6" stroke="var(--brand)" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
      ),
    },
    incloud: {
      label: 'In iCloud',
      color: 'var(--dim)',
      icon: <span style={{ fontSize: 10 }}>☁</span>,
    },
    archive: {
      label: 'Archive',
      color: 'var(--dim)',
      icon: <span style={{ fontSize: 10 }}>📦</span>,
    },
    ready: {
      label: 'Ready',
      color: 'var(--good)',
      icon: (
        <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
          <path d="M2 5l2.5 2.5 3.5-4" stroke="var(--good)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      ),
    },
  }

  const config = configs[status] || configs.ready

  return (
    <span style={{
      display: 'inline-flex',
      alignItems: 'center',
      gap: 4,
      padding: '2px 8px',
      borderRadius: 20,
      fontSize: 11,
      fontWeight: 600,
      color: config.color,
      background: `${config.color}18`,
      border: `1px solid ${config.color}30`,
      whiteSpace: 'nowrap',
    }}>
      {config.icon}
      {config.label}
    </span>
  )
}

// ── Circular progress ────────────────────────────────────────────────────────

function CircularProgress({ percent }: { percent: number }) {
  const r = 14
  const circumference = 2 * Math.PI * r
  const offset = circumference - (percent / 100) * circumference

  return (
    <svg width="36" height="36" viewBox="0 0 36 36">
      <circle cx="18" cy="18" r={r} fill="none" stroke="rgba(255,159,10,0.2)" strokeWidth="3" />
      <circle
        cx="18" cy="18" r={r}
        fill="none"
        stroke="var(--warn)"
        strokeWidth="3"
        strokeLinecap="round"
        strokeDasharray={circumference}
        strokeDashoffset={offset}
        transform="rotate(-90 18 18)"
        style={{ transition: 'stroke-dashoffset 0.3s ease' }}
      />
      <text x="18" y="22" textAnchor="middle" fontSize="9" fill="var(--warn)" fontWeight="600">
        {percent}%
      </text>
    </svg>
  )
}

// ── Project card ─────────────────────────────────────────────────────────────

function ProjectCard({ project }: { project: ProjectInfo }) {
  const { activeProjectId, setActiveProjectId, upsertProject, removeProject, downloadProgress, addToast, setProjects } = useStore()
  const [expanded, setExpanded] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const isActive = activeProjectId === project.id

  const progress = downloadProgress[project.id]
  const overallPercent = progress ? progress.percent : 0

  const handleOpen = async (e: React.MouseEvent) => {
    e.stopPropagation()
    try {
      await window.edithub.openProject(project.id)
      setActiveProjectId(project.id)
      addToast({ type: 'success', message: `Opening ${project.name} in DaVinci Resolve` })
    } catch (err: any) {
      addToast({ type: 'error', message: `Failed to open: ${err.message}` })
    }
  }

  const handleArchive = async (e: React.MouseEvent) => {
    e.stopPropagation()
    try {
      await window.edithub.archiveProject(project.id)
      upsertProject({ ...project, status: 'archive' })
      addToast({ type: 'info', message: `${project.name} archived to iCloud` })
    } catch (err: any) {
      addToast({ type: 'error', message: `Archive failed: ${err.message}` })
    }
  }

  const handleDelete = async (e: React.MouseEvent) => {
    e.stopPropagation()
    if (!confirming) {
      setConfirming(true)
      setTimeout(() => setConfirming(false), 3000)
      return
    }
    try {
      await window.edithub.deleteProject(project.id)
      removeProject(project.id)
      addToast({ type: 'info', message: `${project.name} deleted` })
    } catch (err: any) {
      addToast({ type: 'error', message: `Delete failed: ${err.message}` })
    }
  }

  const handleCancelDownload = async (e: React.MouseEvent) => {
    e.stopPropagation()
    await window.edithub.cancelDownload(project.id)
    addToast({ type: 'info', message: 'Download cancelled' })
  }

  const handleRestore = async (e: React.MouseEvent) => {
    e.stopPropagation()
    try {
      await window.edithub.restoreProject(project.id)
      upsertProject({ ...project, status: 'ready' })
      addToast({ type: 'success', message: `${project.name} restored from iCloud` })
      const list = await window.edithub.listProjects()
      setProjects(list as any)
    } catch (err: any) {
      addToast({ type: 'error', message: `Restore failed: ${err.message}` })
    }
  }

  const handleShowInExplorer = (e: React.MouseEvent) => {
    e.stopPropagation()
    if (project.folderPath) {
      window.edithub.showInExplorer(project.folderPath)
    }
  }

  return (
    <div
      className="card"
      style={{
        padding: '14px 16px',
        cursor: 'pointer',
        border: isActive
          ? '1px solid rgba(47,140,255,0.4)'
          : '1px solid var(--sep)',
        transition: 'transform 0.18s var(--ease-spring), border-color 0.2s ease',
        animation: 'slide-in 0.25s var(--ease-out) both',
      }}
      onClick={() => setExpanded((e) => !e)}
    >
      {/* Header row */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        gap: 12,
      }}>
        {/* Project icon / progress indicator */}
        {project.status === 'downloading' && overallPercent > 0 ? (
          <CircularProgress percent={overallPercent} />
        ) : (
          <div style={{
            width: 36,
            height: 36,
            borderRadius: 10,
            background: isActive ? 'rgba(47,140,255,0.15)' : 'rgba(255,255,255,0.06)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexShrink: 0,
          }}>
            <IconFolder size={18} color={isActive ? 'var(--accent)' : 'var(--dim)'} />
          </div>
        )}

        {/* Project info */}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{
              fontSize: 15,
              fontWeight: 600,
              color: 'var(--txt)',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
            }}>
              {project.name}
            </span>
            <StatusBadge
              status={project.status}
              progress={overallPercent || undefined}
            />
          </div>
          <div style={{
            display: 'flex',
            gap: 12,
            marginTop: 3,
            fontSize: 12,
            color: 'var(--dim)',
          }}>
            <span>{formatDate(project.lastOpenedAt)}</span>
            {project.sizeBytes != null && project.sizeBytes > 0 && (
              <span>{formatBytes(project.sizeBytes)}</span>
            )}
          </div>
        </div>

        {/* Action buttons */}
        <div
          style={{
            display: 'flex',
            gap: 4,
            opacity: expanded ? 1 : 0,
            transition: 'opacity 0.2s ease',
          }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLDivElement).style.opacity = '1'
          }}
        >
          {project.status === 'archive' ? (
            <button
              className="btn-ghost"
              onClick={handleRestore}
              title="Restore from iCloud"
              style={{ padding: '4px 10px', borderRadius: 8, fontSize: 12, color: 'var(--accent)', display: 'flex', alignItems: 'center', gap: 4 }}
            >
              <IconCloud size={14} color="var(--accent)" />
              Restore
            </button>
          ) : (
            <button
              className="btn-ghost"
              onClick={handleOpen}
              title="Open in DaVinci Resolve"
              style={{ padding: '4px 8px', borderRadius: 8, display: 'flex', alignItems: 'center', gap: 4, fontSize: 12, color: 'var(--accent)' }}
            >
              <IconDaVinci size={14} color="var(--accent)" />
              Open
            </button>
          )}

          {project.status === 'downloading' && (
            <button
              className="btn-ghost"
              onClick={handleCancelDownload}
              title="Cancel download"
              style={{ padding: '4px 8px', borderRadius: 8, fontSize: 12, color: 'var(--warn)' }}
            >
              Cancel
            </button>
          )}

          {project.status !== 'archive' && project.status !== 'downloading' && (
            <button
              className="btn-ghost"
              onClick={handleArchive}
              title="Archive to iCloud"
              style={{ padding: '4px 8px', borderRadius: 8, fontSize: 12 }}
            >
              <IconArchive size={14} />
            </button>
          )}

          {project.folderPath && (
            <button
              className="btn-ghost"
              onClick={handleShowInExplorer}
              title="Show in Explorer"
              style={{ padding: '4px 8px', borderRadius: 8, fontSize: 12 }}
            >
              <IconFolder size={14} />
            </button>
          )}

          <button
            className="btn-ghost"
            onClick={handleDelete}
            title={confirming ? 'Click again to confirm delete' : 'Delete project'}
            style={{
              padding: '4px 8px', borderRadius: 8, fontSize: 12,
              color: confirming ? 'var(--bad)' : undefined,
              background: confirming ? 'rgba(255,59,48,0.1)' : undefined,
            }}
          >
            <IconTrash size={14} color={confirming ? 'var(--bad)' : undefined} />
            {confirming && 'Confirm?'}
          </button>
        </div>

        {/* Expand chevron */}
        <svg
          width="14"
          height="14"
          viewBox="0 0 14 14"
          fill="none"
          stroke="var(--dim)"
          strokeWidth="1.5"
          strokeLinecap="round"
          style={{
            transform: expanded ? 'rotate(180deg)' : 'rotate(0deg)',
            transition: 'transform 0.25s var(--ease-spring)',
            flexShrink: 0,
          }}
        >
          <path d="M3 5l4 4 4-4" />
        </svg>
      </div>

      {/* Expanded: file list + download progress */}
      {expanded && (
        <div style={{
          marginTop: 12,
          paddingTop: 12,
          borderTop: '1px solid var(--sep)',
          animation: 'slide-in 0.2s var(--ease-out) both',
        }}>
          {project.footageUrls.length > 0 ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              <p style={{ fontSize: 11, color: 'var(--dim)', textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: 4 }}>
                Footage URLs
              </p>
              {project.footageUrls.map((url, i) => {
                const urlProgress = project.downloadProgress?.[url]
                return (
                  <div key={i} style={{
                    background: 'rgba(255,255,255,0.04)',
                    borderRadius: 8,
                    padding: '8px 10px',
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 4,
                  }}>
                    <div style={{
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      gap: 8,
                    }}>
                      <span style={{
                        fontSize: 12,
                        color: 'var(--dim)',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        whiteSpace: 'nowrap',
                        flex: 1,
                      }}>
                        {url.split('/').pop()?.slice(0, 60) || url.slice(0, 60)}
                      </span>
                      {urlProgress != null && (
                        <span style={{ fontSize: 11, color: 'var(--warn)', fontWeight: 600, flexShrink: 0 }}>
                          {urlProgress}%
                        </span>
                      )}
                    </div>
                    {urlProgress != null && urlProgress < 100 && (
                      <div style={{
                        height: 3,
                        borderRadius: 2,
                        background: 'rgba(255,255,255,0.1)',
                        overflow: 'hidden',
                      }}>
                        <div style={{
                          height: '100%',
                          width: `${urlProgress}%`,
                          background: 'var(--warn)',
                          borderRadius: 2,
                          transition: 'width 0.3s ease',
                        }} />
                      </div>
                    )}
                  </div>
                )
              })}
            </div>
          ) : (
            <p style={{ fontSize: 13, color: 'var(--dim)', textAlign: 'center', padding: '8px 0' }}>
              No footage URLs
            </p>
          )}
        </div>
      )}
    </div>
  )
}

// ── New project form ─────────────────────────────────────────────────────────

function NewProjectForm({ onClose }: { onClose: () => void }) {
  const { addToast, setProjects } = useStore()
  const [name, setName] = useState('')
  const [urls, setUrls] = useState('')
  const [loading, setLoading] = useState(false)

  const handleCreate = async () => {
    if (!name.trim()) return

    const urlList = urls
      .split('\n')
      .map((u) => u.trim())
      .filter(Boolean)

    setLoading(true)
    try {
      await window.edithub.createProject(name.trim(), urlList)
      const updated = await window.edithub.listProjects()
      setProjects(updated as any)
      addToast({
        type: 'success',
        message: `Project "${name}" created${urlList.length > 0 ? ` — downloading ${urlList.length} file(s)` : ''}`,
      })
      onClose()
    } catch (err: any) {
      addToast({ type: 'error', message: `Failed: ${err.message}` })
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{
      background: 'var(--card)',
      borderRadius: 'var(--radius)',
      padding: '20px',
      border: '1px solid var(--sep)',
      boxShadow: 'var(--shadow-card)',
      animation: 'pop-in 0.3s var(--ease-spring) both',
      display: 'flex',
      flexDirection: 'column',
      gap: 16,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <h3 style={{ fontSize: 16, fontWeight: 600 }}>New Project</h3>
        <button
          className="btn-ghost"
          onClick={onClose}
          style={{ padding: '4px 8px', borderRadius: 8 }}
        >
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
            <path d="M2 2l10 10M12 2L2 12" stroke="var(--dim)" strokeWidth="1.5" strokeLinecap="round" />
          </svg>
        </button>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <label style={{ fontSize: 12, color: 'var(--dim)' }}>Project Name</label>
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="e.g. MyVideo_2026"
          autoFocus
          onKeyDown={(e) => e.key === 'Enter' && handleCreate()}
        />
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <label style={{ fontSize: 12, color: 'var(--dim)' }}>
          Footage URLs{' '}
          <span style={{ opacity: 0.5 }}>(Google Drive / Dropbox, one per line)</span>
        </label>
        <textarea
          value={urls}
          onChange={(e) => setUrls(e.target.value)}
          placeholder={'https://drive.google.com/file/d/...\nhttps://www.dropbox.com/s/...'}
          rows={4}
          style={{ resize: 'vertical', minHeight: 80 }}
        />
      </div>

      <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
        <button
          className="btn btn-secondary"
          onClick={onClose}
          disabled={loading}
        >
          Cancel
        </button>
        <button
          className="btn btn-primary"
          onClick={handleCreate}
          disabled={!name.trim() || loading}
          style={{ opacity: !name.trim() || loading ? 0.5 : 1 }}
        >
          {loading ? (
            <span style={{
              display: 'inline-block',
              width: 12,
              height: 12,
              border: '2px solid rgba(255,255,255,0.3)',
              borderTopColor: '#fff',
              borderRadius: '50%',
              animation: 'spin 0.7s linear infinite',
            }} />
          ) : (
            <IconPlus size={14} color="#fff" />
          )}
          Create Project
        </button>
      </div>
    </div>
  )
}

// ── Projects screen ──────────────────────────────────────────────────────────

export default function Projects() {
  const { projects, setProjects } = useStore()
  const [showNewForm, setShowNewForm] = useState(false)
  const [search, setSearch] = useState('')

  useEffect(() => {
    window.edithub.listProjects().then((list) => setProjects(list as any)).catch(() => {})
  }, [])

  const filtered = projects.filter((p) =>
    p.name.toLowerCase().includes(search.toLowerCase())
  )

  const activeProjects = filtered.filter((p) => p.status !== 'archive')
  const archivedProjects = filtered.filter((p) => p.status === 'archive')

  return (
    <div style={{
      height: '100%',
      overflow: 'auto',
      padding: '16px',
      display: 'flex',
      flexDirection: 'column',
      gap: 12,
    }}>
      {/* Toolbar */}
      <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
        <div style={{ flex: 1, position: 'relative' }}>
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
            placeholder="Search projects…"
            style={{ paddingLeft: 32 }}
          />
        </div>
        <button
          className="btn btn-primary"
          onClick={() => setShowNewForm((v) => !v)}
          style={{ flexShrink: 0 }}
        >
          <IconPlus size={14} color="#fff" />
          New Project
        </button>
      </div>

      {/* New project form */}
      {showNewForm && (
        <NewProjectForm onClose={() => setShowNewForm(false)} />
      )}

      {/* Active projects */}
      {activeProjects.length === 0 && !showNewForm && (
        <div style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 12,
          color: 'var(--dim)',
          animation: 'fade-in 0.3s ease both',
        }}>
          <IconFolder size={40} color="var(--dim)" />
          <p style={{ fontSize: 15 }}>No projects yet</p>
          <button
            className="btn btn-primary"
            onClick={() => setShowNewForm(true)}
          >
            <IconPlus size={14} color="#fff" />
            Create your first project
          </button>
        </div>
      )}

      {activeProjects.length > 0 && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {activeProjects.map((p) => (
            <ProjectCard key={p.id} project={p} />
          ))}
        </div>
      )}

      {/* Archived projects */}
      {archivedProjects.length > 0 && (
        <>
          <div style={{
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            padding: '4px 0',
          }}>
            <div style={{ flex: 1, height: 1, background: 'var(--sep)' }} />
            <span style={{ fontSize: 12, color: 'var(--dim)', whiteSpace: 'nowrap' }}>
              Archive ({archivedProjects.length})
            </span>
            <div style={{ flex: 1, height: 1, background: 'var(--sep)' }} />
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {archivedProjects.map((p) => (
              <ProjectCard key={p.id} project={p} />
            ))}
          </div>
        </>
      )}
    </div>
  )
}
