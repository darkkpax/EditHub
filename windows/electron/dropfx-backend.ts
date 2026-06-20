import { ChildProcess, spawn } from 'child_process'
import * as path from 'path'
import * as fs from 'fs'
import * as http from 'http'

const BACKEND_PORT = 8765
const STARTUP_TIMEOUT_MS = 10000

export class DropFXBackend {
  private process: ChildProcess | null = null
  private running = false

  async start(): Promise<void> {
    const backendPath = this.findBackendScript()
    if (!backendPath) {
      throw new Error('DropFX backend script not found')
    }

    return new Promise((resolve, reject) => {
      const args = this._useExe ? [] : [backendPath]
      const cmd = this._useExe
        ? backendPath
        : (process.platform === 'win32' ? 'python' : 'python3')

      this.process = spawn(cmd, args, {
        stdio: ['ignore', 'pipe', 'pipe'],
        env: {
          ...process.env,
          DROPFX_PORT: String(BACKEND_PORT),
        },
      })

      this.process.stdout?.on('data', (data: Buffer) => {
        console.log('[DropFX]', data.toString().trim())
      })

      this.process.stderr?.on('data', (data: Buffer) => {
        console.warn('[DropFX stderr]', data.toString().trim())
      })

      this.process.on('error', (err) => {
        console.warn('DropFX backend process error:', err.message)
        reject(err)
      })

      this.process.on('exit', (code) => {
        console.log('DropFX backend exited with code', code)
        this.running = false
      })

      // Poll until backend responds or timeout
      const startTime = Date.now()
      const poll = () => {
        this.checkHealth()
          .then(() => {
            this.running = true
            resolve()
          })
          .catch(() => {
            if (Date.now() - startTime > STARTUP_TIMEOUT_MS) {
              reject(new Error('DropFX backend startup timeout'))
              return
            }
            setTimeout(poll, 500)
          })
      }

      setTimeout(poll, 1000) // Give Python a moment to start
    })
  }

  private findBackendScript(): string | null {
    // Prefer pre-built .exe (PyInstaller bundle — no Python needed)
    const exeCandidates = [
      path.join(process.resourcesPath || '', 'assets', 'dropfx_backend.exe'),
      path.join(__dirname, '../../assets', 'dropfx_backend.exe'),
    ]
    for (const c of exeCandidates) {
      if (fs.existsSync(c)) {
        this._useExe = true
        return c
      }
    }
    // Fall back to .py (needs Python installed)
    const pyCandidates = [
      path.join(process.resourcesPath || '', 'assets', 'dropfx_backend.py'),
      path.join(__dirname, '../../assets/dropfx_backend.py'),
      path.join(__dirname, '../../../assets/dropfx_backend.py'),
    ]
    for (const c of pyCandidates) {
      if (fs.existsSync(c)) return c
    }
    return null
  }

  private _useExe = false

  private checkHealth(): Promise<void> {
    return new Promise((resolve, reject) => {
      const req = http.get(
        `http://localhost:${BACKEND_PORT}/health`,
        { timeout: 2000 },
        (res) => {
          if (res.statusCode === 200) resolve()
          else reject(new Error(`Health check failed: ${res.statusCode}`))
        }
      )
      req.on('error', reject)
      req.on('timeout', () => {
        req.destroy()
        reject(new Error('Health check timeout'))
      })
    })
  }

  isRunning(): boolean {
    return this.running
  }

  stop(): void {
    if (this.process) {
      this.process.kill('SIGTERM')
      this.process = null
    }
    this.running = false
  }
}
