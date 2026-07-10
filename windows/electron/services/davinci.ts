import { spawn, execSync } from 'child_process'
import * as fs from 'fs'
import * as path from 'path'

const RESOLVE_SCRIPT_TIMEOUT_MS = 60000

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

export interface LaunchDaVinciResult {
  launched: boolean
  projectReady: boolean
  message?: string
  drpFilePath?: string
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function findBridgeScript(): string | null {
  const candidates = [
    path.join(process.resourcesPath || '', 'assets', 'resolve_project_bridge.py'),
    path.join(__dirname, '../../assets', 'resolve_project_bridge.py'),
    path.join(__dirname, '../../../assets', 'resolve_project_bridge.py'),
  ]
  return candidates.find((candidate) => fs.existsSync(candidate)) || null
}

function findScriptCommand(): string[] | null {
  if (process.platform === 'win32') {
    const fuscriptCandidates = [
      'C:\\Program Files\\Blackmagic Design\\DaVinci Resolve\\fuscript.exe',
      'C:\\Program Files (x86)\\Blackmagic Design\\DaVinci Resolve\\fuscript.exe',
    ]
    for (const candidate of fuscriptCandidates) {
      if (fs.existsSync(candidate)) return [candidate]
    }
  }

  const candidates = process.platform === 'win32'
    ? ['python', 'py', 'python3']
    : ['python3', 'python']

  for (const candidate of candidates) {
    try {
      execSync(`${candidate} --version`, { stdio: 'ignore', timeout: 3000 })
      return [candidate]
    } catch {}
  }
  return null
}

function runResolveBridge(
  action: 'open' | 'export',
  projectFolder: string,
  drpFilePath: string
): Promise<string> {
  return new Promise((resolve, reject) => {
    const bridgeScript = findBridgeScript()
    if (!bridgeScript) {
      reject(new Error('Resolve bridge script not found'))
      return
    }

    const command = findScriptCommand()
    if (!command) {
      reject(new Error('DaVinci Resolve script runner not found'))
      return
    }

    const args = [
      bridgeScript,
      '--action', action,
      '--project-name', path.basename(projectFolder),
      '--project-folder', projectFolder,
      '--drp-path', drpFilePath,
      '--timeout', '45',
    ]

    const proc = spawn(command[0], [...command.slice(1), ...args], {
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'],
    })

    let stdout = ''
    let stderr = ''
    const timer = setTimeout(() => {
      proc.kill()
      reject(new Error('Resolve scripting timed out'))
    }, RESOLVE_SCRIPT_TIMEOUT_MS)

    proc.stdout?.on('data', (data: Buffer) => { stdout += data.toString() })
    proc.stderr?.on('data', (data: Buffer) => { stderr += data.toString() })
    proc.on('error', (err) => {
      clearTimeout(timer)
      reject(err)
    })
    proc.on('close', (code) => {
      clearTimeout(timer)
      if (code === 0) resolve(stdout.trim())
      else reject(new Error((stderr || stdout || `Resolve scripting failed with code ${code}`).trim()))
    })
  })
}

export async function launchDaVinci(
  davinciPath: string,
  projectFolder: string
): Promise<LaunchDaVinciResult> {
  const resolvePath = davinciPath || getDefaultDaVinciPath()

  if (!fs.existsSync(resolvePath)) {
    console.warn('DaVinci Resolve not found at:', resolvePath)
    return { launched: false, projectReady: false, message: 'DaVinci Resolve not found' }
  }

  const drpFilePath = path.join(projectFolder, `${path.basename(projectFolder)}.drp`)

  try {
    if (!isResolveRunning()) {
      const proc = spawn(resolvePath, [], {
        detached: true,
        stdio: 'ignore',
      })
      proc.unref()
      await delay(3000)
    }

    const message = await runResolveBridge('open', projectFolder, drpFilePath)
    return { launched: true, projectReady: true, message, drpFilePath }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    console.error('Failed to prepare DaVinci Resolve project:', err)
    return { launched: true, projectReady: false, message, drpFilePath }
  }
}

export async function exportDaVinciProject(
  projectFolder: string
): Promise<{ exported: boolean; message?: string; drpFilePath: string }> {
  const drpFilePath = path.join(projectFolder, `${path.basename(projectFolder)}.drp`)
  try {
    const message = await runResolveBridge('export', projectFolder, drpFilePath)
    return { exported: true, message, drpFilePath }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return { exported: false, message, drpFilePath }
  }
}

export function findDrpFile(projectFolder: string): string | null {
  try {
    const entries = fs.readdirSync(projectFolder)
    for (const entry of entries) {
      if (!entry.toLowerCase().endsWith('.drp')) continue

      const drpPath = path.join(projectFolder, entry)
      const stat = fs.statSync(drpPath)
      if (stat.isFile() && stat.size > 0) return drpPath

      console.warn('Ignoring empty DaVinci project export:', drpPath)
    }
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
