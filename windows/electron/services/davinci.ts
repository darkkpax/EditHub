import { spawn, execSync } from 'child_process'
import * as fs from 'fs'
import * as path from 'path'
import * as os from 'os'

function getDefaultDaVinciPath(): string {
  if (process.platform === 'win32') {
    return 'C:\\Program Files\\Blackmagic Design\\DaVinci Resolve\\Resolve.exe'
  }
  return '/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/MacOS/Resolve'
}

export function isResolveRunning(): boolean {
  try {
    if (process.platform === 'win32') {
      const result = execSync(
        'tasklist /FI "IMAGENAME eq Resolve.exe" /NH',
        { encoding: 'utf-8', timeout: 3000 }
      )
      return result.toLowerCase().includes('resolve.exe')
    } else {
      const result = execSync('pgrep -x "DaVinci Resolve"', {
        encoding: 'utf-8',
        timeout: 3000,
      })
      return result.trim().length > 0
    }
  } catch {
    return false
  }
}

export function launchDaVinci(
  davinciPath: string,
  drpFilePath?: string
): boolean {
  const resolvePath = davinciPath || getDefaultDaVinciPath()

  if (!fs.existsSync(resolvePath)) {
    console.warn('DaVinci Resolve not found at:', resolvePath)
    return false
  }

  try {
    const args = drpFilePath ? [drpFilePath] : []
    const proc = spawn(resolvePath, args, {
      detached: true,
      stdio: 'ignore',
    })
    proc.unref()
    return true
  } catch (err) {
    console.error('Failed to launch DaVinci Resolve:', err)
    return false
  }
}

export function findDrpFile(projectFolder: string): string | null {
  try {
    const entries = fs.readdirSync(projectFolder)
    const drpFile = entries.find((e) => e.endsWith('.drp'))
    if (drpFile) return path.join(projectFolder, drpFile)
  } catch {}
  return null
}

export function autoDetectDaVinci(): string {
  const candidates: string[] = []

  if (process.platform === 'win32') {
    candidates.push(
      'C:\\Program Files\\Blackmagic Design\\DaVinci Resolve\\Resolve.exe',
      'C:\\Program Files (x86)\\Blackmagic Design\\DaVinci Resolve\\Resolve.exe'
    )
    // Also check Program Files via env
    const pf = process.env['ProgramFiles']
    const pfx86 = process.env['ProgramFiles(x86)']
    if (pf) {
      candidates.push(
        path.join(pf, 'Blackmagic Design', 'DaVinci Resolve', 'Resolve.exe')
      )
    }
    if (pfx86) {
      candidates.push(
        path.join(pfx86, 'Blackmagic Design', 'DaVinci Resolve', 'Resolve.exe')
      )
    }
  } else {
    candidates.push(
      '/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/MacOS/Resolve'
    )
  }

  for (const c of candidates) {
    if (fs.existsSync(c)) return c
  }

  return getDefaultDaVinciPath()
}
