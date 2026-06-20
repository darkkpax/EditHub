import * as fs from 'fs'
import * as path from 'path'
import { v4 as uuidv4 } from 'uuid'
import AdmZip from 'adm-zip'

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
  createdAt: string
  lastOpenedAt: string
  footageUrls: string[]
  status: ProjectStatus
  downloadProgress: Record<string, number>
  folderPath?: string
  sizeBytes?: number
}

const PROJECT_MANIFEST = '.edithub.json'

export function readProjectInfo(projectFolder: string): ProjectInfo | null {
  try {
    const manifestPath = path.join(projectFolder, PROJECT_MANIFEST)
    if (!fs.existsSync(manifestPath)) return null
    const raw = fs.readFileSync(manifestPath, 'utf-8')
    const data = JSON.parse(raw) as ProjectInfo
    data.folderPath = projectFolder
    return data
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

export function extractZipProject(zipPath: string, destFolder: string): string | null {
  try {
    const zip = new AdmZip(zipPath)
    zip.extractAllTo(destFolder, true)
    fs.unlinkSync(zipPath)
    // Find the extracted folder (usually same name as zip without .zip)
    const baseName = path.basename(zipPath, '.zip')
    const candidate = path.join(destFolder, baseName)
    if (fs.existsSync(candidate)) return candidate
    // Fallback: find any new directory
    const entries = fs.readdirSync(destFolder, { withFileTypes: true })
    for (const e of entries) {
      if (e.isDirectory()) return path.join(destFolder, e.name)
    }
    return null
  } catch (err) {
    console.warn('Failed to extract ZIP project:', err)
    return null
  }
}

export function listProjectsInFolder(projectsFolder: string): ProjectInfo[] {
  const results: ProjectInfo[] = []
  try {
    const entries = fs.readdirSync(projectsFolder, { withFileTypes: true })
    for (const entry of entries) {
      const entryPath = path.join(projectsFolder, entry.name)

      // Handle ZIP archives: extract and treat as normal project
      if (!entry.isDirectory() && entry.name.endsWith('.zip')) {
        const extracted = extractZipProject(entryPath, projectsFolder)
        if (extracted) {
          const info = readProjectInfo(extracted)
          if (info) {
            info.folderPath = extracted
            info.sizeBytes = getFolderSizeBytes(extracted)
            results.push(info)
          }
        }
        continue
      }

      if (!entry.isDirectory()) continue
      const info = readProjectInfo(entryPath)
      if (info) {
        info.folderPath = entryPath
        info.sizeBytes = getFolderSizeBytes(entryPath)
        results.push(info)
      }
    }
  } catch (err) {
    console.warn('Error listing projects:', err)
  }
  return results.sort(
    (a, b) =>
      new Date(b.lastOpenedAt).getTime() - new Date(a.lastOpenedAt).getTime()
  )
}

export function createProjectFolderStructure(
  parentFolder: string,
  projectName: string
): string {
  const projectFolder = path.join(parentFolder, projectName)
  const subfolders = ['SFX', 'Music', 'Footage', 'Graphics', 'Docs']

  if (!fs.existsSync(projectFolder)) {
    fs.mkdirSync(projectFolder, { recursive: true })
  }

  for (const sub of subfolders) {
    const subPath = path.join(projectFolder, sub)
    if (!fs.existsSync(subPath)) {
      fs.mkdirSync(subPath)
    }
  }

  // Create empty .drp placeholder
  const drpPath = path.join(projectFolder, `${projectName}.drp`)
  if (!fs.existsSync(drpPath)) {
    fs.writeFileSync(drpPath, '', 'utf-8')
  }

  return projectFolder
}
