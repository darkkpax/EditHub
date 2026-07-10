import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useStore, ProjectInfo, ProjectStatus } from '../store/useStore'
import {
  IconArchive,
  IconCloud,
  IconDaVinci,
  IconFolder,
  IconPlus,
  IconSearch,
  IconTrash,
} from '../components/icons/icons'

interface FolderEntry {
  name: string
  path: string
  type: 'file' | 'folder'
  sizeBytes?: number
  children?: FolderEntry[]
}

interface ProjectPreview {
  videoPath: string
  dataUrl: string | null
}

const MONTH_INDEX: Record<string, number> = {
  JANUARY: 0, FEBRUARY: 1, MARCH: 2, APRIL: 3,
  MAY: 4, JUNE: 5, JULY: 6, AUGUST: 7,
  SEPTEMBER: 8, OCTOBER: 9, NOVEMBER: 10, DECEMBER: 11,
}

function formatBytes(bytes?: number): string {
  if (!bytes) return '0 B'
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`
}

function fmtMonth(m: string): string {
  return m.charAt(0).toUpperCase() + m.slice(1).toLowerCase()
}

function projectPeriod(project: ProjectInfo): string {
  if (project.year && project.month) {
    return `${fmtMonth(project.month)} ${project.year}`
  }
  const date = new Date(project.createdAt || project.lastOpenedAt)
  if (Number.isNaN(date.getTime())) return 'Projects'
  return date.toLocaleDateString('en-US', { year: 'numeric', month: 'long' })
}

function projectSortTime(project: ProjectInfo): number {
  const year = Number(project.year)
  const monthKey = project.month?.toUpperCase()
  if (year && monthKey && monthKey in MONTH_INDEX) {
    const base = Date.UTC(year, MONTH_INDEX[monthKey], 1)
    const updated = new Date(project.lastOpenedAt || project.createdAt).getTime()
    return base + (Number.isFinite(updated) ? updated % (31 * 24 * 60 * 60 * 1000) : 0)
  }
  return new Date(project.lastOpenedAt || project.createdAt).getTime() || 0
}

function sortNewest(projects: ProjectInfo[]): ProjectInfo[] {
  return [...projects].sort((a, b) => projectSortTime(b) - projectSortTime(a))
}

function StatusBadge({ status }: { status: ProjectStatus }) {
  const map: Record<ProjectStatus, { label: string; color: string }> = {
    active: { label: 'Active', color: 'var(--accent)' },
    downloading: { label: 'Downloading', color: 'var(--warn)' },
    uploading: { label: 'Uploading', color: 'var(--brand)' },
    incloud: { label: 'iCloud', color: 'var(--dim)' },
    archive: { label: 'iCloud', color: 'var(--warn)' },
    ready: { label: 'Ready', color: 'var(--good)' },
  }
  const cfg = map[status] || map.ready
  return (
    <span style={{
      color: cfg.color,
      background: `${cfg.color}18`,
      border: `1px solid ${cfg.color}30`,
      borderRadius: 999,
      padding: '2px 7px',
      fontSize: 11,
      fontWeight: 650,
      lineHeight: 1.4,
    }}>
      {cfg.label}
    </span>
  )
}

function NewProjectPopover({ onClose }: { onClose: () => void }) {
  const { addToast, setProjects } = useStore()
  const [name, setName] = useState('')
  const [urlInput, setUrlInput] = useState('')
  const [urls, setUrls] = useState<string[]>([])
  const [loading, setLoading] = useState(false)
  const [flying, setFlying] = useState(false)

  const addUrl = () => {
    const trimmed = urlInput.trim()
    if (trimmed && !urls.includes(trimmed)) {
      setUrls((prev) => [...prev, trimmed])
    }
    setUrlInput('')
  }

  const removeUrl = (idx: number) => setUrls((prev) => prev.filter((_, i) => i !== idx))

  const handleUrlKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') { e.preventDefault(); addUrl() }
  }

  const create = async () => {
    if (!name.trim()) return
    setLoading(true)
    try {
      await window.edithub.createProject(name.trim(), urls)
      const updated = await window.edithub.listProjects()
      setProjects(updated as any)
      addToast({ type: 'success', message: `Project "${name.trim()}" created` })
      setFlying(true)
      window.setTimeout(onClose, 420)
    } catch (err: any) {
      addToast({ type: 'error', message: `Create failed: ${err.message}` })
      setLoading(false)
    }
  }

  return (
    <>
      <div onClick={onClose} style={{
        position: 'absolute',
        inset: 0,
        zIndex: 19,
        background: 'transparent',
      }} />
      <div style={{
      position: 'absolute',
      right: 22,
      bottom: 84,
      width: 360,
      zIndex: 20,
      background: 'rgba(44,44,48,0.52)',
      border: '1px solid rgba(255,255,255,0.14)',
      borderRadius: 16,
      boxShadow: '0 24px 80px rgba(0,0,0,0.52)',
      backdropFilter: 'blur(14px) saturate(1.18)',
      WebkitBackdropFilter: 'blur(14px) saturate(1.18)',
      padding: 18,
      display: 'flex',
      flexDirection: 'column',
      gap: 14,
      transformOrigin: 'calc(100% - 26px) calc(100% + 34px)',
      animation: flying
        ? 'project-popover-fly 0.42s var(--ease-spring) both'
        : 'project-popover-in 0.32s var(--ease-spring) both',
    }}>
      <label style={{ display: 'grid', gap: 6, fontSize: 12, color: 'var(--dim)' }}>
        <span style={{ fontWeight: 650 }}>Project name</span>
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          autoFocus
          placeholder=""
          onKeyDown={(e) => e.key === 'Enter' && create()}
        />
      </label>

      <div style={{ display: 'grid', gap: 6, fontSize: 12, color: 'var(--dim)' }}>
        <span style={{ fontWeight: 650 }}>URL</span>
        <div style={{ display: 'flex', gap: 6 }}>
          <input
            value={urlInput}
            onChange={(e) => setUrlInput(e.target.value)}
            onKeyDown={handleUrlKeyDown}
            placeholder=""
            style={{ flex: 1 }}
          />
          <button
            className="btn btn-secondary"
            onClick={addUrl}
            disabled={!urlInput.trim()}
            style={{ flexShrink: 0 }}
          >
            Add
          </button>
        </div>
        {urls.length > 0 && (
          <div style={{ display: 'grid', gap: 4 }}>
            {urls.map((url, idx) => {
              const host = url.includes('drive.google.com') ? 'Google Drive'
                : url.includes('dropbox.com') ? 'Dropbox'
                : (url.split('/')[2] ?? 'Link')
              return (
                <div key={idx} style={{
                  display: 'flex', alignItems: 'center', gap: 8,
                  padding: '4px 8px', borderRadius: 7,
                  background: 'rgba(255,255,255,0.05)', border: '1px solid var(--sep)',
                }}>
                  <span style={{ fontSize: 11, color: 'var(--accent)', fontWeight: 600, flexShrink: 0 }}>{host}</span>
                  <span style={{ flex: 1, fontSize: 10, color: 'var(--dim)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{url}</span>
                  <button onClick={() => removeUrl(idx)} style={{ color: 'var(--dim)', fontSize: 13, lineHeight: 1, padding: '0 2px' }}>×</button>
                </div>
              )
            })}
          </div>
        )}
      </div>

      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
        <button className="btn btn-primary" onClick={create} disabled={loading || !name.trim()} style={{ opacity: loading || !name.trim() ? 0.55 : 1 }}>
          <IconPlus size={14} color="#fff" />
          Create
        </button>
      </div>
      </div>
    </>
  )
}

function fileUrl(filePath: string): string {
  return `file:///${filePath.replace(/\\/g, '/')}`
}

function useProjectPreview(project: ProjectInfo, enabled: boolean) {
  const [preview, setPreview] = useState<ProjectPreview | null>(null)

  useEffect(() => {
    let alive = true
    if (!enabled || !project.folderPath || project.status === 'archive') {
      setPreview(null)
      return
    }
    window.edithub.getProjectThumbnail(project.folderPath)
      .then((res: any) => { if (alive) setPreview(res || null) })
      .catch(() => { if (alive) setPreview(null) })
    return () => { alive = false }
  }, [project.folderPath, project.status, enabled])

  return preview
}

function ProjectIcon({
  project,
  size = 40,
  previewEnabled = false,
}: {
  project: ProjectInfo
  size?: number
  previewEnabled?: boolean
}) {
  const preview = useProjectPreview(project, previewEnabled)
  return (
    <div style={{
      width: size, height: size,
      borderRadius: size > 50 ? 13 : 9,
      display: 'grid', placeItems: 'center',
      background: project.status === 'archive' ? 'rgba(255,159,10,0.15)' : 'rgba(47,140,255,0.14)',
      flexShrink: 0, overflow: 'hidden',
    }}>
      {preview?.dataUrl ? (
        <img src={preview.dataUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
      ) : preview?.videoPath ? (
        <video
          src={fileUrl(preview.videoPath)}
          muted preload="metadata"
          style={{ width: '100%', height: '100%', objectFit: 'cover' }}
          onLoadedMetadata={(e) => { (e.currentTarget as HTMLVideoElement).currentTime = 1 }}
        />
      ) : project.status === 'archive'
        ? <IconArchive size={Math.round(size * 0.48)} color="var(--warn)" />
        : <IconFolder size={Math.round(size * 0.48)} color="var(--accent)" />}
    </div>
  )
}

interface ContextMenuState {
  x: number
  y: number
  projectIds: string[]
}

function ContextMenu({
  menu, projects, onClose, onOpen, onArchive, onReveal, onDelete,
}: {
  menu: ContextMenuState
  projects: ProjectInfo[]
  onClose: () => void
  onOpen: (id: string) => void
  onArchive: (ids: string[]) => void
  onReveal: (id: string) => void
  onDelete: (ids: string[]) => void
}) {
  const ref = useRef<HTMLDivElement>(null)
  const single = menu.projectIds.length === 1 ? menu.projectIds[0] : null
  const singleProject = single ? projects.find((p) => p.id === single) : null

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose()
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [onClose])

  const item = (label: string, onClick: () => void, danger = false) => (
    <button
      onClick={() => { onClick(); onClose() }}
      style={{
        display: 'block', width: '100%', textAlign: 'left',
        padding: '7px 14px', fontSize: 13,
        color: danger ? '#ff453a' : 'var(--txt)',
        background: 'transparent',
        borderRadius: 6,
        cursor: 'pointer',
      }}
      onMouseEnter={(e) => { (e.currentTarget as HTMLElement).style.background = 'rgba(255,255,255,0.08)' }}
      onMouseLeave={(e) => { (e.currentTarget as HTMLElement).style.background = 'transparent' }}
    >
      {label}
    </button>
  )

  return (
    <div
      ref={ref}
      style={{
        position: 'fixed',
        left: menu.x, top: menu.y,
        zIndex: 1000,
        background: 'rgba(38,38,42,0.74)',
        border: '1px solid rgba(255,255,255,0.14)',
        borderRadius: 10,
        boxShadow: '0 18px 54px rgba(0,0,0,0.46)',
        backdropFilter: 'blur(20px) saturate(1.2)',
        WebkitBackdropFilter: 'blur(20px) saturate(1.2)',
        animation: 'popover-in 0.22s var(--ease-spring) both',
        padding: '4px 0',
        minWidth: 180,
      }}
    >
      {single && singleProject?.status !== 'archive' && item('Open in DaVinci', () => onOpen(single))}
      {single && item('Reveal in Explorer', () => onReveal(single))}
      <div style={{ height: 1, background: 'var(--sep)', margin: '3px 0' }} />
      {item('Archive to iCloud', () => onArchive(menu.projectIds))}
      {item(`Delete${menu.projectIds.length > 1 ? ` (${menu.projectIds.length})` : ''}`, () => onDelete(menu.projectIds), true)}
    </div>
  )
}

function ProjectRow({
  project, selected, multiSelected, onSelect, onContextMenu,
}: {
  project: ProjectInfo
  selected: boolean
  multiSelected: boolean
  onSelect: (e: React.MouseEvent) => void
  onContextMenu: (e: React.MouseEvent) => void
}) {
  return (
    <button
      onClick={onSelect}
      onContextMenu={onContextMenu}
      style={{
        width: '100%',
        display: 'flex',
        alignItems: 'center',
        gap: 11,
        padding: '8px 10px',
        borderRadius: 10,
        textAlign: 'left',
        background: multiSelected
          ? 'rgba(47,140,255,0.22)'
          : selected
          ? 'rgba(47,140,255,0.16)'
          : 'transparent',
        color: 'var(--txt)',
        outline: multiSelected ? '2px solid rgba(47,140,255,0.4)' : 'none',
      }}
    >
      <ProjectIcon project={project} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
          <span style={{ fontSize: 14, fontWeight: 650, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {project.name}
          </span>
          {project.status === 'active' && <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--good)', flexShrink: 0 }} />}
        </div>
        <div style={{ display: 'flex', gap: 8, color: 'var(--dim)', fontSize: 12, marginTop: 2 }}>
          <span>{projectPeriod(project)}</span>
          {project.sizeBytes ? <span>{formatBytes(project.sizeBytes)}</span> : null}
        </div>
      </div>
    </button>
  )
}

function ProjectSidebar({
  projects, selectedId, onSelect, onBulkArchive, onBulkDelete,
}: {
  projects: ProjectInfo[]
  selectedId: string | null
  onSelect: (project: ProjectInfo) => void
  onBulkArchive: (ids: string[]) => void
  onBulkDelete: (ids: string[]) => void
}) {
  const { addToast } = useStore()
  const [search, setSearch] = useState('')
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [contextMenu, setContextMenu] = useState<ContextMenuState | null>(null)
  const lastClickedIdRef = useRef<string | null>(null)

  const filtered = useMemo(() => {
    const q = search.toLowerCase()
    return sortNewest(projects.filter((p) => {
      if (p.status === 'archive') return false
      return p.name.toLowerCase().includes(q)
    }))
  }, [projects, search])

  const groups = useMemo(() => {
    const buckets = new Map<string, ProjectInfo[]>()
    filtered.forEach((project) => {
      const key = projectPeriod(project)
      buckets.set(key, [...(buckets.get(key) || []), project])
    })
    return Array.from(buckets.entries())
  }, [filtered])

  const handleRowClick = (project: ProjectInfo, e: React.MouseEvent) => {
    if (e.shiftKey && lastClickedIdRef.current) {
      const allIds = filtered.map((p) => p.id)
      const fromIdx = allIds.indexOf(lastClickedIdRef.current)
      const toIdx = allIds.indexOf(project.id)
      if (fromIdx !== -1 && toIdx !== -1) {
        const [lo, hi] = fromIdx < toIdx ? [fromIdx, toIdx] : [toIdx, fromIdx]
        const rangeIds = allIds.slice(lo, hi + 1)
        setSelectedIds((prev) => new Set([...prev, ...rangeIds]))
        return
      }
    }
    if (e.ctrlKey || e.metaKey) {
      setSelectedIds((prev) => {
        const next = new Set(prev)
        next.has(project.id) ? next.delete(project.id) : next.add(project.id)
        return next
      })
      lastClickedIdRef.current = project.id
      return
    }
    setSelectedIds(new Set())
    lastClickedIdRef.current = project.id
    onSelect(project)
  }

  const handleContextMenu = (project: ProjectInfo, e: React.MouseEvent) => {
    e.preventDefault()
    const ids = selectedIds.has(project.id) && selectedIds.size > 1
      ? Array.from(selectedIds)
      : [project.id]
    if (!selectedIds.has(project.id)) {
      setSelectedIds(new Set([project.id]))
      onSelect(project)
    }
    setContextMenu({ x: e.clientX, y: e.clientY, projectIds: ids })
  }

  const handleOpen = (id: string) => {
    const p = projects.find((proj) => proj.id === id)
    if (p) onSelect(p)
  }

  const handleReveal = (id: string) => {
    const p = projects.find((proj) => proj.id === id)
    if (p?.folderPath) {
      window.edithub.showInExplorer(p.folderPath).catch((err: any) => {
        addToast({ type: 'error', message: err?.message || 'Cannot open folder' })
      })
    }
  }

  return (
    <aside style={{
      width: 330, minWidth: 300, maxWidth: 430,
      borderRight: '1px solid var(--sep)',
      background: 'rgba(255,255,255,0.025)',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <div style={{
        padding: '10px 16px',
        background: 'rgba(28,28,30,0.72)',
        backdropFilter: 'blur(18px) saturate(1.2)',
        WebkitBackdropFilter: 'blur(18px) saturate(1.2)',
        position: 'relative', zIndex: 1,
      }}>
        <div style={{ position: 'relative' }}>
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search projects"
            style={{ paddingLeft: 34, height: 38, borderRadius: 999 }}
          />
          <span style={{ position: 'absolute', left: 12, top: 11, pointerEvents: 'none' }}>
            <IconSearch size={15} color="var(--dim)" />
          </span>
        </div>
      </div>

      <div style={{ overflow: 'auto', padding: '0 10px 90px' }}>
        {groups.length === 0 ? (
          <div style={{ color: 'var(--dim)', fontSize: 13, padding: 16 }}>No projects found.</div>
        ) : groups.map(([group, items]) => (
          <section key={group} style={{ marginBottom: 14 }}>
            <div style={{
              color: 'var(--dim)', fontSize: 11, fontWeight: 700,
              letterSpacing: '0.06em', textTransform: 'uppercase',
              padding: '8px 10px 6px',
            }}>
              {group}
            </div>
            <div style={{ display: 'grid', gap: 2 }}>
              {items.map((project) => (
                <ProjectRow
                  key={project.id}
                  project={project}
                  selected={project.id === selectedId}
                  multiSelected={selectedIds.has(project.id)}
                  onSelect={(e) => handleRowClick(project, e)}
                  onContextMenu={(e) => handleContextMenu(project, e)}
                />
              ))}
            </div>
          </section>
        ))}
      </div>

      {contextMenu && (
        <ContextMenu
          menu={contextMenu}
          projects={projects}
          onClose={() => setContextMenu(null)}
          onOpen={handleOpen}
          onArchive={(ids) => { setSelectedIds(new Set()); onBulkArchive(ids) }}
          onReveal={handleReveal}
          onDelete={(ids) => { setSelectedIds(new Set()); onBulkDelete(ids) }}
        />
      )}
    </aside>
  )
}

function FolderTree({ project }: { project: ProjectInfo }) {
  const [entries, setEntries] = useState<FolderEntry[]>([])

  useEffect(() => {
    let alive = true
    if (!project.folderPath || project.status === 'archive') {
      setEntries([]); return
    }
    window.edithub.listProjectFolders(project.folderPath)
      .then((list: FolderEntry[]) => {
        if (!alive) return
        setEntries(list)
      })
      .catch(() => { if (!alive) return; setEntries([]) })
    return () => { alive = false }
  }, [project.folderPath, project.status])

  const renderEntry = (entry: FolderEntry, depth = 0): React.ReactNode => (
    <div key={entry.path}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10,
        padding: '8px 10px', paddingLeft: 10 + depth * 16,
        borderRadius: 9,
        background: depth === 0 ? 'rgba(255,255,255,0.045)' : 'transparent',
        border: depth === 0 ? '1px solid var(--sep)' : 'none',
        color: entry.type === 'folder' ? 'var(--txt)' : 'var(--dim)',
        fontSize: entry.type === 'folder' ? 13 : 12,
      }}>
        <IconFolder size={15} color={entry.type === 'folder' ? 'var(--dim)' : 'var(--sep)'} />
        <span style={{ fontWeight: entry.type === 'folder' ? 600 : 400, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{entry.name}</span>
        {entry.type === 'file' && entry.sizeBytes != null && (
          <span style={{ marginLeft: 'auto', color: 'var(--dim)', fontSize: 11 }}>{formatBytes(entry.sizeBytes)}</span>
        )}
      </div>
      {entry.children?.slice(0, 24).map((child) => renderEntry(child, depth + 1))}
    </div>
  )

  return (
    <div style={{ display: 'grid', gap: 6 }}>
      {entries.length ? entries.map((e) => renderEntry(e)) : (
        <EmptyDetail kind="folder" title="No Folders" message="This project folder is empty or unavailable." compact />
      )}
    </div>
  )
}

function ProjectDetail({ project }: { project: ProjectInfo }) {
  const { addToast, setActiveProjectId, setProjects, upsertProject, removeProject } = useStore()
  const [confirmDelete, setConfirmDelete] = useState(false)

  const openProject = async () => {
    try {
      const result = await window.edithub.openProject(project.id)
      setActiveProjectId(project.id)
      if (result?.projectReady === false) {
        addToast({ type: 'info', message: result.message || `DaVinci opened. Project automation is unavailable.` })
      } else {
        addToast({ type: 'success', message: `Opening ${project.name}` })
      }
    } catch (err: any) {
      addToast({ type: 'error', message: `Open failed: ${err.message}` })
    }
  }

  const refresh = async () => {
    const list = await window.edithub.listProjects()
    setProjects(list as any)
  }

  const archiveProject = async () => {
    try {
      await window.edithub.archiveProject(project.id)
      upsertProject({ ...project, status: 'archive' })
      addToast({ type: 'info', message: `${project.name} sent to iCloud` })
      refresh()
    } catch (err: any) {
      addToast({ type: 'error', message: `Unload failed: ${err.message}` })
    }
  }

  const restoreProject = async () => {
    try {
      await window.edithub.restoreProject(project.id)
      addToast({ type: 'success', message: `${project.name} restored` })
      refresh()
    } catch (err: any) {
      addToast({ type: 'error', message: `Restore failed: ${err.message}` })
    }
  }

  const deleteProject = async () => {
    if (!confirmDelete) {
      setConfirmDelete(true)
      setTimeout(() => setConfirmDelete(false), 3000)
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

  return (
    <section style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      <header style={{
        minHeight: 104, padding: '14px 18px', borderBottom: '1px solid var(--sep)',
        background: 'rgba(28,28,30,0.72)',
        backdropFilter: 'blur(18px) saturate(1.2)',
        WebkitBackdropFilter: 'blur(18px) saturate(1.2)',
        display: 'flex', alignItems: 'stretch', gap: 14,
      }}>
        <ProjectIcon project={project} size={76} previewEnabled />
        <div style={{ minWidth: 0, display: 'flex', flexDirection: 'column', justifyContent: 'space-between', padding: '2px 0' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
            <h2 style={{ fontSize: 24, lineHeight: 1.15, fontWeight: 750, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{project.name}</h2>
            <StatusBadge status={project.status} />
          </div>
          <p style={{ color: 'var(--dim)', fontSize: 13 }}>
            {projectPeriod(project)}
            {project.sizeBytes ? ` · ${formatBytes(project.sizeBytes)}` : ''}
          </p>
        </div>
        <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'flex-end', gap: 10 }}>
          {project.status === 'archive' ? (
            <button className="btn btn-primary" onClick={restoreProject}><IconCloud size={15} color="#fff" />Restore</button>
          ) : (
            <button className="btn btn-primary" onClick={openProject}><IconDaVinci size={15} color="#fff" />Open</button>
          )}
          {project.folderPath && (
            <button className="btn btn-secondary" onClick={() => {
              window.edithub.showInExplorer(project.folderPath!).catch((err: any) => {
                addToast({ type: 'error', message: err?.message || 'Cannot open folder' })
              })
            }}><IconFolder size={15} />Reveal</button>
          )}
          {project.status !== 'archive' && (
            <button className="btn btn-secondary" onClick={archiveProject}>
              <svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <path d="M11.5 10.5H10.5A3 3 0 0 1 7.5 7.5a2.5 2.5 0 0 1 4.95-.5H13a2 2 0 0 1 0 4z" />
                <path d="M4 10.5A2 2 0 0 1 3.5 6.6 3.5 3.5 0 0 1 10 8" />
                <line x1="7" y1="13" x2="7" y2="10" />
                <polyline points="5.5,11.5 7,10 8.5,11.5" />
              </svg>
              Archive
            </button>
          )}
          <button className={confirmDelete ? 'btn btn-danger' : 'btn btn-secondary'} onClick={deleteProject}>
            <IconTrash size={15} color={confirmDelete ? '#fff' : 'currentColor'} />
            {confirmDelete ? 'Confirm' : 'Delete'}
          </button>
        </div>
      </header>

      <div style={{ flex: 1, overflow: 'auto', padding: 18, display: 'grid', gridTemplateColumns: 'minmax(280px, 1fr)', gap: 16, alignContent: 'start' }}>
        <div>
          <h3 style={{ fontSize: 13, color: 'var(--dim)', textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: 10 }}>Folder tree</h3>
          {project.status === 'archive' ? (
            <EmptyDetail kind="cloud" title="Stored in iCloud" message="Restore this project to work with its local folder tree." />
          ) : (
            <FolderTree project={project} />
          )}
        </div>
      </div>
    </section>
  )
}

function EmptyDetail({ kind, title, message, compact = false }: { kind: 'folder' | 'cloud'; title: string; message: string; compact?: boolean }) {
  return (
    <div style={{
      minHeight: compact ? 120 : 260,
      display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
      textAlign: 'center', gap: 9, color: 'var(--dim)',
      border: '1px dashed var(--sep)', borderRadius: 14, padding: 22,
    }}>
      {kind === 'cloud' ? <IconCloud size={28} color="var(--dim)" /> : <IconFolder size={28} color="var(--dim)" />}
      <strong style={{ color: 'var(--txt)' }}>{title}</strong>
      <p style={{ fontSize: 13, lineHeight: 1.45, maxWidth: 280 }}>{message}</p>
    </div>
  )
}

function ExtractionOverlay({ progress }: { progress: { current: number; total: number; name: string } | null }) {
  if (!progress) return null
  const pct = progress.total > 0 ? Math.round((progress.current / progress.total) * 100) : 0
  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 50,
      background: 'rgba(20,20,22,0.92)',
      display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center', gap: 16,
    }}>
      <IconCloud size={36} color="var(--accent)" />
      <div style={{ textAlign: 'center' }}>
        <div style={{ fontWeight: 700, fontSize: 16, marginBottom: 4 }}>Extracting archives…</div>
        <div style={{ color: 'var(--dim)', fontSize: 13, maxWidth: 280, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {progress.name}
        </div>
      </div>
      <div style={{ width: 300, background: 'rgba(255,255,255,0.1)', borderRadius: 999, overflow: 'hidden', height: 6 }}>
        <div style={{ width: `${pct}%`, height: '100%', background: 'var(--accent)', borderRadius: 999, transition: 'width 0.3s ease' }} />
      </div>
      <div style={{ color: 'var(--dim)', fontSize: 12 }}>{progress.current} of {progress.total}</div>
    </div>
  )
}

export default function Projects() {
  const { projects, setProjects, addToast, removeProject, upsertProject, setArchivesProgress } = useStore()
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [showCreate, setShowCreate] = useState(false)

  const loadProjects = useCallback(async () => {
    const startedAt = performance.now()
    window.edithub.debugLog?.('INFO', 'projects load start')
    try {
      const list = await window.edithub.listProjects()
      const sorted = sortNewest(list as ProjectInfo[])
      setProjects(sorted as any)
      setSelectedId((prev) => prev ?? sorted[0]?.id ?? null)
      window.edithub.debugLog?.('INFO', 'projects load done', {
        ms: Math.round(performance.now() - startedAt),
        count: sorted.length,
      })
    } catch (err: any) {
      window.edithub.debugLog?.('WARN', 'projects load failed', {
        ms: Math.round(performance.now() - startedAt),
        message: err?.message || String(err),
      })
    }
  }, [setProjects])

  useEffect(() => {
    // Subscribe to archive extraction events
    const unsubProgress = window.edithub.onArchivesProgress((p) =>
      setArchivesProgress({ current: p.current, total: p.total, name: p.name })
    )
    const unsubDone = window.edithub.onArchivesDone((result) => {
      setArchivesProgress(null)
      if (result.extracted > 0) {
        addToast({ type: 'success', message: `Extracted ${result.extracted} archive${result.extracted !== 1 ? 's' : ''}` })
        loadProjects()
      }
    })

    loadProjects()

    return () => { unsubProgress(); unsubDone() }
  }, [])

  useEffect(() => {
    const sorted = sortNewest(projects)
    if (!selectedId && sorted.length) setSelectedId(sorted[0].id)
    if (selectedId && !projects.some((p) => p.id === selectedId)) setSelectedId(sorted[0]?.id || null)
  }, [projects, selectedId])

  const selected = projects.find((p) => p.id === selectedId) || null

  const handleBulkArchive = useCallback(async (ids: string[]) => {
    for (const id of ids) {
      try {
        await window.edithub.archiveProject(id)
        const p = projects.find((proj) => proj.id === id)
        if (p) upsertProject({ ...p, status: 'archive' })
      } catch (err: any) {
        addToast({ type: 'error', message: `Unload failed: ${err.message}` })
      }
    }
    if (ids.length > 1) addToast({ type: 'info', message: `${ids.length} projects sent to iCloud` })
    const list = await window.edithub.listProjects()
    setProjects(list as any)
  }, [projects, upsertProject, addToast, setProjects])

  const handleBulkDelete = useCallback(async (ids: string[]) => {
    for (const id of ids) {
      try {
        await window.edithub.deleteProject(id)
        removeProject(id)
      } catch (err: any) {
        addToast({ type: 'error', message: `Delete failed: ${err.message}` })
      }
    }
    if (ids.length > 1) addToast({ type: 'info', message: `${ids.length} projects deleted` })
  }, [removeProject, addToast])

  return (
    <div style={{ height: '100%', display: 'flex', overflow: 'hidden', position: 'relative' }}>
      <ProjectSidebar
        projects={projects}
        selectedId={selectedId}
        onSelect={(project) => setSelectedId(project.id)}
        onBulkArchive={handleBulkArchive}
        onBulkDelete={handleBulkDelete}
      />
      {selected ? (
        <ProjectDetail project={selected} />
      ) : (
        <div style={{ flex: 1, padding: 18 }}>
          <EmptyDetail kind="folder" title="No Projects" message="Create your first project with the plus button." />
        </div>
      )}

      {showCreate && <NewProjectPopover onClose={() => setShowCreate(false)} />}
      <button
        onClick={() => setShowCreate((v) => !v)}
        title="New project"
        style={{
          position: 'absolute', right: 22, bottom: 22,
          width: 56, height: 56, borderRadius: '50%',
          background: 'var(--accent)', color: '#fff',
          display: 'grid', placeItems: 'center',
          boxShadow: '0 12px 32px rgba(47,140,255,0.34)',
          transform: showCreate ? 'rotate(45deg)' : 'none',
          transition: 'transform 0.22s var(--ease-spring)',
          zIndex: 25,
        }}
      >
        <IconPlus size={24} color="#fff" />
      </button>
    </div>
  )
}
