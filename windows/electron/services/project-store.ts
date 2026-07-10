import * as fs from 'fs'
import * as path from 'path'
import * as crypto from 'crypto'
import { v4 as uuidv4 } from 'uuid'
import { spawn } from 'child_process'

export type ProjectStatus =
  | 'active'
  | 'downloading'
  | 'uploading'
  | 'incloud'
  | 'archive'
  | 'ready'

export interface ProjectInfo {
  id: string
  name: string
  year?: string
  month?: string
  createdAt: string
  lastOpenedAt: string
  footageUrls: string[]
  status: ProjectStatus
  downloadProgress: Record<string, number>
  folderPath?: string
  sizeBytes?: number
}

const PROJECT_MANIFEST = '.edithub.json'
const PROJECT_METADATA = '.edithub-metadata.json'
export const DEFAULT_PROJECT_FOLDERS = [
  'FOOTAGE',
  'SFX',
  'MUSIC',
  'READY VIDEOS',
  'MISC',
  path.join('VOICE', 'ENCHANCE'),
  path.join('VOICE', 'NOT ENCHANCE'),
  'DOCS',
  'GRAPHICS',
  'B-ROLL',
  'SUBS',
]
const VIDEO_EXTENSIONS = new Set(['.mp4', '.mov', '.m4v', '.avi', '.mkv', '.webm', '.braw'])

export function readProjectInfo(projectFolder: string): ProjectInfo | null {
  try {
    const manifestPath = path.join(projectFolder, PROJECT_MANIFEST)
    if (!fs.existsSync(manifestPath)) return null
    const raw = fs.readFileSync(manifestPath, 'utf-8')
    const data = JSON.parse(raw) as ProjectInfo
    data.folderPath = projectFolder
    if (!data.year || !data.month) {
      const parts = projectFolder.split(path.sep)
      data.month = data.month || parts[parts.length - 2]
      data.year = data.year || parts[parts.length - 3]
    }
    return data
  } catch {
    return null
  }
}

function readJson(filePath: string): any | null {
  try {
    if (!fs.existsSync(filePath)) return null
    return JSON.parse(fs.readFileSync(filePath, 'utf-8'))
  } catch {
    return null
  }
}

function stableIdFromPath(projectFolder: string): string {
  return crypto.createHash('sha1').update(projectFolder.toLowerCase()).digest('hex').slice(0, 32)
}

function findMacManifest(projectFolder: string): any | null {
  const projectName = path.basename(projectFolder)
  return readJson(path.join(projectFolder, `${projectName}.edithub`))
}

function readMacProjectInfo(projectFolder: string, year?: string, month?: string): ProjectInfo | null {
  try {
    if (!fs.existsSync(projectFolder) || !fs.statSync(projectFolder).isDirectory()) return null

    const name = path.basename(projectFolder)
    const metadata = readJson(path.join(projectFolder, PROJECT_METADATA))
    const archiveManifest = findMacManifest(projectFolder)
    const stat = fs.statSync(projectFolder)

    const createdAt =
      stat.birthtime?.toISOString?.() ||
      stat.ctime.toISOString()

    return {
      id: metadata?.projectId || archiveManifest?.projectId || stableIdFromPath(projectFolder),
      name,
      year,
      month,
      createdAt,
      lastOpenedAt: stat.mtime.toISOString(),
      footageUrls: metadata?.footageLinks || archiveManifest?.footageLinks || [],
      status: archiveManifest ? 'archive' : 'ready',
      downloadProgress: {},
      folderPath: projectFolder,
    }
  } catch {
    return null
  }
}

export function writeProjectInfo(
  projectFolder: string,
  info: ProjectInfo
): void {
  const manifestPath = path.join(projectFolder, PROJECT_MANIFEST)
  fs.writeFileSync(manifestPath, JSON.stringify(info, null, 2), 'utf-8')
}

export function createProjectInfo(name: string, urls: string[]): ProjectInfo {
  return {
    id: uuidv4(),
    name,
    year: new Date().getFullYear().toString(),
    month: new Date().toLocaleString('en-US', { month: 'long' }).toUpperCase(),
    createdAt: new Date().toISOString(),
    lastOpenedAt: new Date().toISOString(),
    footageUrls: urls,
    status: urls.length > 0 ? 'downloading' : 'ready',
    downloadProgress: {},
  }
}

export function getFolderSizeBytes(folderPath: string): number {
  let total = 0
  try {
    const entries = fs.readdirSync(folderPath, { withFileTypes: true })
    for (const entry of entries) {
      const fullPath = path.join(folderPath, entry.name)
      if (entry.isDirectory()) {
        total += getFolderSizeBytes(fullPath)
      } else {
        try {
          total += fs.statSync(fullPath).size
        } catch {}
      }
    }
  } catch {}
  return total
}

export function extractZipProject(zipPath: string, destFolder: string): Promise<string | null> {
  return new Promise((resolve) => {
    try {
      const baseName = path.basename(zipPath, '.zip')
      const tempDest = path.join(destFolder, `__extracting_${baseName}_${Date.now()}`)
      fs.mkdirSync(tempDest, { recursive: true })

      const escapePsArg = (s: string) => `'${s.replace(/'/g, "''")}'`
      const ps = spawn('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-Command',
        `Expand-Archive -LiteralPath ${escapePsArg(zipPath)} -DestinationPath ${escapePsArg(tempDest)} -Force`,
      ])

      ps.on('close', (code) => {
        if (code !== 0) {
          try { fs.rmSync(tempDest, { recursive: true, force: true }) } catch {}
          resolve(null)
          return
        }
        try { fs.unlinkSync(zipPath) } catch {}

        let finalPath: string
        try {
          const entries = fs.readdirSync(tempDest, { withFileTypes: true })
          const subDirs = entries.filter((e) => e.isDirectory())
          if (subDirs.length === 1) {
            const inner = path.join(tempDest, subDirs[0].name)
            finalPath = path.join(destFolder, subDirs[0].name)
            fs.renameSync(inner, finalPath)
            try { fs.rmdirSync(tempDest) } catch {}
          } else {
            finalPath = path.join(destFolder, baseName)
            fs.renameSync(tempDest, finalPath)
          }
        } catch {
          finalPath = tempDest
        }
        resolve(finalPath)
      })

      ps.on('error', () => {
        try { fs.rmSync(tempDest, { recursive: true, force: true }) } catch {}
        resolve(null)
      })
    } catch {
      resolve(null)
    }
  })
}

export function listProjectsInFolder(projectsFolder: string): ProjectInfo[] {
  const results: ProjectInfo[] = []
  const seen = new Set<string>()

  const pushProject = (info: ProjectInfo | null) => {
    if (!info) return
    if (seen.has(info.id)) return
    seen.add(info.id)
    results.push(info)
  }

  try {
    const scanProjectDir = (projectPath: string, year?: string, month?: string) => {
      const winInfo = readProjectInfo(projectPath)
      if (winInfo) {
        winInfo.folderPath = projectPath
        pushProject(winInfo)
        return
      }
      pushProject(readMacProjectInfo(projectPath, year, month))
    }

    const scanFolder = (folder: string, depth = 0, year?: string, month?: string) => {
      if (depth > 3) return
      const entries = fs.readdirSync(folder, { withFileTypes: true })
      for (const entry of entries) {
        if (
          entry.name.startsWith('.') ||
          entry.name === 'node_modules' ||
          entry.name.toLowerCase().startsWith('__extracting_')
        ) continue
        const entryPath = path.join(folder, entry.name)

        if (!entry.isDirectory()) continue

        const nextYear = /^\d{4}$/.test(entry.name) ? entry.name : year
        const nextMonth = year && depth <= 2 ? entry.name : month

        const hasWinManifest = fs.existsSync(path.join(entryPath, PROJECT_MANIFEST))
        const hasMacManifest = fs.existsSync(path.join(entryPath, `${entry.name}.edithub`))
        const hasMetadata = fs.existsSync(path.join(entryPath, PROJECT_METADATA))
        const hasKnownProjectFolders = ['SFX', 'Music', 'Footage', 'Graphics', 'Docs', 'FOOTAGE', 'READY VIDEOS', 'READY VIDEO', 'VOICE', 'B-ROLL', 'SUBS', 'MISC']
          .some((folderName) => fs.existsSync(path.join(entryPath, folderName)))

        if (hasWinManifest || hasMacManifest || hasMetadata || (year && month && hasKnownProjectFolders)) {
          scanProjectDir(entryPath, year, month)
          continue
        }

        scanFolder(entryPath, depth + 1, nextYear, nextMonth)
      }
    }

    if (fs.existsSync(projectsFolder)) {
      scanFolder(projectsFolder)
    }

    // Also support selecting the project folder itself.
    if (results.length === 0) {
      const own = readProjectInfo(projectsFolder) || readMacProjectInfo(projectsFolder)
      if (own) pushProject(own)
    }

  } catch (err) {
    console.warn('Error listing projects:', err)
  }
  return results.sort((a, b) => projectSortTime(b) - projectSortTime(a))
}

export function listArchivedProjectsInFolder(archiveFolder: string): ProjectInfo[] {
  const results: ProjectInfo[] = []
  try {
    if (!fs.existsSync(archiveFolder)) return []
    const walk = (dir: string, depth = 0) => {
      if (depth > 4) return
      const entries = fs.readdirSync(dir, { withFileTypes: true })
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name)
        if (entry.isDirectory()) {
          walk(fullPath, depth + 1)
          continue
        }
        if (!entry.name.endsWith('.zip')) continue
        const name = path.basename(entry.name, '.zip')
        const stat = fs.statSync(fullPath)
        const parts = path.relative(archiveFolder, fullPath).split(path.sep)
        const year = parts.length >= 3 ? parts[0] : ''
        const month = parts.length >= 3 ? parts[1] : ''
        results.push({
          id: stableIdFromPath(fullPath),
          name,
          year,
          month,
          createdAt: stat.birthtime.toISOString(),
          lastOpenedAt: stat.mtime.toISOString(),
          footageUrls: [],
          status: 'archive',
          downloadProgress: {},
          folderPath: fullPath,
          sizeBytes: stat.size,
        })
      }
    }
    walk(archiveFolder)
  } catch (err) {
    console.warn('Error listing archived projects:', err)
  }
  return results
}

export function createProjectFolderStructure(
  parentFolder: string,
  projectName: string
): string {
  const now = new Date()
  const year = now.getFullYear().toString()
  const month = now.toLocaleString('en-US', { month: 'long' }).toUpperCase()
  const projectFolder = path.join(parentFolder, year, month, projectName)
  const subfolders = DEFAULT_PROJECT_FOLDERS

  if (!fs.existsSync(projectFolder)) {
    fs.mkdirSync(projectFolder, { recursive: true })
  }

  for (const sub of subfolders) {
    const subPath = path.join(projectFolder, sub)
    if (!fs.existsSync(subPath)) {
      fs.mkdirSync(subPath, { recursive: true })
    }
  }

  return projectFolder
}

export interface FolderEntry {
  name: string
  path: string
  type: 'file' | 'folder'
  sizeBytes?: number
  children?: FolderEntry[]
}

export function listProjectFolders(projectFolder: string): FolderEntry[] {
  const readDir = (dir: string, depth = 0): FolderEntry[] => {
    if (!fs.existsSync(dir) || depth > 3) return []
    return fs.readdirSync(dir, { withFileTypes: true })
      .filter((entry) => !entry.name.startsWith('.'))
      .sort((a, b) => Number(b.isDirectory()) - Number(a.isDirectory()) || a.name.localeCompare(b.name))
      .map((entry) => {
        const fullPath = path.join(dir, entry.name)
        if (entry.isDirectory()) {
          return {
            name: entry.name,
            path: fullPath,
            type: 'folder' as const,
            children: readDir(fullPath, depth + 1),
          }
        }
        let sizeBytes = 0
        try { sizeBytes = fs.statSync(fullPath).size } catch {}
        return { name: entry.name, path: fullPath, type: 'file' as const, sizeBytes }
      })
  }
  return readDir(projectFolder)
}

export function findProjectPreviewVideo(projectFolder: string): string | null {
  const preferred = ['FOOTAGE', 'Footage', 'READY VIDEOS', 'READY VIDEO', 'Ready Videos']
  for (const folder of preferred) {
    const root = path.join(projectFolder, folder)
    const found = findFirstVideo(root)
    if (found) return found
  }
  return findFirstVideo(projectFolder)
}

const MONTH_INDEX: Record<string, number> = {
  JANUARY: 0,
  FEBRUARY: 1,
  MARCH: 2,
  APRIL: 3,
  MAY: 4,
  JUNE: 5,
  JULY: 6,
  AUGUST: 7,
  SEPTEMBER: 8,
  OCTOBER: 9,
  NOVEMBER: 10,
  DECEMBER: 11,
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

export async function extractArchivesToProjects(
  sourceFolders: string[],
  onProgress: (p: { current: number; total: number; name: string }) => void
): Promise<{ extracted: number; total: number }> {
  interface ZipEntry { zipPath: string; year: string; month: string; name: string }

  const findZips = (dir: string, year?: string, month?: string): ZipEntry[] => {
    if (!fs.existsSync(dir)) return []
    let entries: fs.Dirent[]
    try { entries = fs.readdirSync(dir, { withFileTypes: true }) } catch { return [] }
    const results: ZipEntry[] = []
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name)
      if (entry.isDirectory()) {
        if (/^\d{4}$/.test(entry.name)) {
          results.push(...findZips(fullPath, entry.name, undefined))
        } else if (year && !month) {
          results.push(...findZips(fullPath, year, entry.name))
        }
      } else if (entry.name.endsWith('.zip') && year && month) {
        results.push({ zipPath: fullPath, year, month, name: path.basename(entry.name, '.zip') })
      }
    }
    return results
  }

  const all: ZipEntry[] = []
  const seen = new Set<string>()
  for (const folder of sourceFolders) {
    for (const z of findZips(folder)) {
      const key = `${z.year}/${z.month}/${z.name}`
      if (!seen.has(key)) { seen.add(key); all.push(z) }
    }
  }

  let extracted = 0
  for (let i = 0; i < all.length; i++) {
    const { zipPath, year, month, name } = all[i]
    onProgress({ current: i + 1, total: all.length, name })
    try {
      // Extract IN PLACE — into the same folder the zip lives in
      const destParent = path.dirname(zipPath)
      const expectedDest = path.join(destParent, name)
      if (fs.existsSync(expectedDest)) {
        try { fs.unlinkSync(zipPath) } catch {}
        continue
      }
      const result = await extractZipProject(zipPath, destParent)
      if (result && fs.existsSync(result)) {
        const manifestPath = path.join(result, '.edithub.json')
        if (!fs.existsSync(manifestPath)) {
          const stat = fs.statSync(result)
          const info: ProjectInfo = {
            id: stableIdFromPath(result),
            name: path.basename(result),
            year,
            month,
            createdAt: stat.birthtime?.toISOString?.() || stat.ctime.toISOString(),
            lastOpenedAt: stat.mtime.toISOString(),
            footageUrls: [],
            status: 'ready',
            downloadProgress: {},
          }
          writeProjectInfo(result, info)
        }
        extracted++
      }
    } catch (err) {
      console.warn(`Failed to extract ${zipPath}:`, err)
    }
  }

  return { extracted, total: all.length }
}

/**
 * Removes orphaned `__extracting_*` temp folders left behind when a zip
 * extraction crashed or the app was killed mid-extraction. A temp dir is
 * removed if either (a) a real sibling folder with the cleaned name already
 * exists (so the temp is a duplicate), or (b) it is older than `staleMs`
 * (an in-progress extraction always has a fresh mtime). Returns how many
 * dirs were removed and how many bytes were freed.
 */
export function sweepExtractingDirs(
  folders: string[],
  staleMs = 60 * 60 * 1000
): { removed: number; bytesFreed: number } {
  let removed = 0
  let bytesFreed = 0
  const now = Date.now()
  const seenRoots = new Set<string>()

  const cleanName = (name: string): string =>
    name.replace(/^__extracting_/i, '').replace(/_\d{10,}.*$/, '')

  const walk = (dir: string, depth = 0): void => {
    if (depth > 4 || !fs.existsSync(dir)) return
    let entries: fs.Dirent[]
    try { entries = fs.readdirSync(dir, { withFileTypes: true }) } catch { return }
    for (const entry of entries) {
      if (!entry.isDirectory()) continue
      const fullPath = path.join(dir, entry.name)
      if (entry.name.toLowerCase().startsWith('__extracting_')) {
        const twin = path.join(dir, cleanName(entry.name))
        let isStale = false
        try { isStale = now - fs.statSync(fullPath).mtimeMs > staleMs } catch {}
        const hasTwin = fs.existsSync(twin) && twin !== fullPath
        if (hasTwin || isStale) {
          try {
            const size = getFolderSizeBytes(fullPath)
            fs.rmSync(fullPath, { recursive: true, force: true })
            if (!fs.existsSync(fullPath)) { removed++; bytesFreed += size }
          } catch (err) {
            console.warn(`Failed to remove stale extracting dir ${fullPath}:`, err)
          }
        }
        continue
      }
      walk(fullPath, depth + 1)
    }
  }

  for (const folder of folders) {
    const resolved = path.resolve(folder)
    if (seenRoots.has(resolved)) continue
    seenRoots.add(resolved)
    walk(resolved)
  }

  if (removed > 0) {
    console.log(`Swept ${removed} stale __extracting_ dir(s), freed ${(bytesFreed / 1e9).toFixed(2)} GB`)
  }
  return { removed, bytesFreed }
}

function findFirstVideo(root: string): string | null {
  if (!fs.existsSync(root)) return null
  try {
    const entries = fs.readdirSync(root, { withFileTypes: true })
    for (const entry of entries) {
      const fullPath = path.join(root, entry.name)
      if (entry.isFile() && VIDEO_EXTENSIONS.has(path.extname(entry.name).toLowerCase())) return fullPath
    }
    for (const entry of entries) {
      if (!entry.isDirectory()) continue
      const found = findFirstVideo(path.join(root, entry.name))
      if (found) return found
    }
  } catch {}
  return null
}
