import * as fs from 'fs'
import * as path from 'path'
import * as https from 'https'
import * as http from 'http'
import { URL } from 'url'
import AdmZip from 'adm-zip'

export interface DownloadProgress {
  projectId: string
  fileUrl: string
  fileName: string
  percent: number
  bytesDownloaded: number
  totalBytes: number
}

export interface DownloadTask {
  projectId: string
  fileUrl: string
  destFolder: string
  cancelled: boolean
}

type ProgressCallback = (progress: DownloadProgress) => void
type CompleteCallback = (projectId: string) => void
type ErrorCallback = (projectId: string, error: string) => void

const MAX_ATTEMPTS = 40
const MAX_BACKOFF_SECONDS = 60

function getBackoffMs(attempt: number): number {
  return Math.min(MAX_BACKOFF_SECONDS, attempt * 5) * 1000
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function parseGoogleDriveUrl(url: string): string | null {
  try {
    const parsed = new URL(url)
    if (
      parsed.hostname === 'drive.google.com' &&
      parsed.pathname.includes('/file/d/')
    ) {
      const match = parsed.pathname.match(/\/file\/d\/([^/]+)/)
      if (match) {
        return `https://drive.google.com/uc?export=download&id=${match[1]}`
      }
    }
    if (parsed.hostname === 'drive.google.com' && parsed.searchParams.has('id')) {
      const id = parsed.searchParams.get('id')
      return `https://drive.google.com/uc?export=download&id=${id}`
    }
  } catch {
    return null
  }
  return null
}

function parseDropboxUrl(url: string): string | null {
  try {
    const parsed = new URL(url)
    if (
      parsed.hostname === 'www.dropbox.com' ||
      parsed.hostname === 'dropbox.com'
    ) {
      parsed.hostname = 'dl.dropboxusercontent.com'
      parsed.searchParams.set('dl', '1')
      return parsed.toString()
    }
  } catch {
    return null
  }
  return null
}

function normalizeUrl(rawUrl: string): string {
  let url = rawUrl.trim()

  // Validate URL
  try {
    new URL(url)
  } catch {
    throw new Error(`Invalid URL: ${rawUrl}`)
  }

  const gdrive = parseGoogleDriveUrl(url)
  if (gdrive) return gdrive

  const dropbox = parseDropboxUrl(url)
  if (dropbox) return dropbox

  return url
}

function shouldRetry(statusCode: number): boolean {
  return (
    statusCode === 408 ||
    statusCode === 425 ||
    statusCode === 429 ||
    statusCode >= 500
  )
}

async function downloadFileWithResume(
  task: DownloadTask,
  fileUrl: string,
  destPath: string,
  onProgress: (bytes: number, total: number) => void
): Promise<void> {
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    if (task.cancelled) {
      throw new Error('CANCELLED')
    }

    // Check existing bytes for resume
    let existingBytes = 0
    if (fs.existsSync(destPath)) {
      existingBytes = fs.statSync(destPath).size
    }

    try {
      await new Promise<void>((resolve, reject) => {
        if (task.cancelled) {
          reject(new Error('CANCELLED'))
          return
        }

        let url: URL
        try {
          url = new URL(fileUrl)
        } catch {
          reject(new Error(`Invalid URL: ${fileUrl}`))
          return
        }

        const isHttps = url.protocol === 'https:'
        const requester = isHttps ? https : http

        const headers: Record<string, string> = {}
        if (existingBytes > 0) {
          headers['Range'] = `bytes=${existingBytes}-`
        }

        const req = requester.get(
          fileUrl,
          { headers },
          (res) => {
            if (task.cancelled) {
              req.destroy()
              reject(new Error('CANCELLED'))
              return
            }

            // Handle redirects
            if (
              res.statusCode &&
              res.statusCode >= 300 &&
              res.statusCode < 400 &&
              res.headers.location
            ) {
              req.destroy()
              downloadFileWithResume(
                task,
                res.headers.location,
                destPath,
                onProgress
              )
                .then(resolve)
                .catch(reject)
              return
            }

            if (res.statusCode && shouldRetry(res.statusCode)) {
              req.destroy()
              reject(
                Object.assign(new Error(`HTTP ${res.statusCode}`), {
                  statusCode: res.statusCode,
                })
              )
              return
            }

            if (
              res.statusCode &&
              res.statusCode !== 200 &&
              res.statusCode !== 206
            ) {
              req.destroy()
              reject(
                Object.assign(new Error(`HTTP ${res.statusCode}`), {
                  statusCode: res.statusCode,
                  permanent: true,
                })
              )
              return
            }

            // Determine total size
            let totalBytes = existingBytes
            const contentLength = res.headers['content-length']
            const contentRange = res.headers['content-range']

            if (contentRange) {
              const match = contentRange.match(/bytes \d+-\d+\/(\d+)/)
              if (match) totalBytes = parseInt(match[1], 10)
            } else if (contentLength) {
              totalBytes = parseInt(contentLength, 10) + existingBytes
            }

            // If server sent 200 (not 206), start fresh
            const writeStream = fs.createWriteStream(destPath, {
              flags: res.statusCode === 206 ? 'a' : 'w',
            })

            let downloaded = existingBytes

            res.on('data', (chunk: Buffer) => {
              if (task.cancelled) {
                req.destroy()
                writeStream.destroy()
                reject(new Error('CANCELLED'))
                return
              }
              downloaded += chunk.length
              // Monotonic: never report less than existing
              const reportBytes = Math.max(downloaded, existingBytes)
              onProgress(reportBytes, totalBytes)
            })

            res.on('end', () => {
              writeStream.end()
              writeStream.on('finish', resolve)
            })

            res.on('error', (err) => {
              writeStream.destroy()
              reject(err)
            })

            res.pipe(writeStream, { end: false })
          }
        )

        req.on('error', (err) => {
          reject(err)
        })

        req.setTimeout(30000, () => {
          req.destroy()
          reject(new Error('Request timeout'))
        })
      })

      return // Success
    } catch (err: unknown) {
      const error = err as Error & { statusCode?: number; permanent?: boolean }
      if (error.message === 'CANCELLED') throw err
      if (error.permanent) throw err

      if (attempt < MAX_ATTEMPTS) {
        const backoff = getBackoffMs(attempt)
        console.log(
          `Download attempt ${attempt} failed: ${error.message}. Retrying in ${backoff / 1000}s`
        )
        await sleep(backoff)
      } else {
        throw new Error(
          `Download failed after ${MAX_ATTEMPTS} attempts: ${error.message}`
        )
      }
    }
  }
}

function getFilenameFromUrl(url: string): string {
  try {
    const parsed = new URL(url)
    const parts = parsed.pathname.split('/')
    const last = parts[parts.length - 1]
    if (last && last.includes('.')) return decodeURIComponent(last)
  } catch {}
  return `download_${Date.now()}`
}

async function autoUnzip(filePath: string, destFolder: string): Promise<void> {
  const ext = path.extname(filePath).toLowerCase()
  if (ext !== '.zip') return

  try {
    const zip = new AdmZip(filePath)
    zip.extractAllTo(destFolder, true)
    fs.unlinkSync(filePath)
    console.log(`Extracted and removed ZIP: ${filePath}`)
  } catch (err) {
    console.warn(`Failed to extract ZIP ${filePath}:`, err)
  }
}

export class Downloader {
  private activeTasks = new Map<string, DownloadTask>()
  private onProgress: ProgressCallback
  private onComplete: CompleteCallback
  private onError: ErrorCallback

  constructor(
    onProgress: ProgressCallback,
    onComplete: CompleteCallback,
    onError: ErrorCallback
  ) {
    this.onProgress = onProgress
    this.onComplete = onComplete
    this.onError = onError
  }

  async startDownloads(
    projectId: string,
    urls: string[],
    destFolder: string
  ): Promise<void> {
    if (!fs.existsSync(destFolder)) {
      fs.mkdirSync(destFolder, { recursive: true })
    }

    const tasks: DownloadTask[] = urls.map((url) => ({
      projectId,
      fileUrl: url,
      destFolder,
      cancelled: false,
    }))

    tasks.forEach((t) => this.activeTasks.set(`${projectId}:${t.fileUrl}`, t))

    try {
      await Promise.all(
        urls.map(async (rawUrl, i) => {
          const task = tasks[i]
          let normalizedUrl: string
          try {
            normalizedUrl = normalizeUrl(rawUrl)
          } catch (err: unknown) {
            this.onError(projectId, (err as Error).message)
            return
          }

          const fileName = getFilenameFromUrl(normalizedUrl)
          const destPath = path.join(destFolder, fileName)

          await downloadFileWithResume(
            task,
            normalizedUrl,
            destPath,
            (bytes, total) => {
              const percent = total > 0 ? Math.round((bytes / total) * 100) : 0
              this.onProgress({
                projectId,
                fileUrl: rawUrl,
                fileName,
                percent: Math.min(percent, 100),
                bytesDownloaded: bytes,
                totalBytes: total,
              })
            }
          )

          // Auto-unzip if needed
          await autoUnzip(destPath, destFolder)
        })
      )

      this.onComplete(projectId)
    } catch (err: unknown) {
      const error = err as Error
      if (error.message === 'CANCELLED') {
        // Clean up partial download files
        urls.forEach((rawUrl) => {
          try {
            const normalized = normalizeUrl(rawUrl)
            const fileName = getFilenameFromUrl(normalized)
            const partialPath = path.join(destFolder, fileName)
            if (fs.existsSync(partialPath)) {
              const stat = fs.statSync(partialPath)
              // Only delete if it's a partial file (not a complete file)
              // Heuristic: file was modified in last 5 min
              if (Date.now() - stat.mtimeMs < 5 * 60_000) {
                fs.unlinkSync(partialPath)
              }
            }
          } catch {}
        })
      } else {
        this.onError(projectId, error.message)
      }
    } finally {
      tasks.forEach((t) =>
        this.activeTasks.delete(`${projectId}:${t.fileUrl}`)
      )
    }
  }

  cancelDownload(projectId: string): void {
    this.activeTasks.forEach((task, key) => {
      if (task.projectId === projectId) {
        task.cancelled = true
      }
    })
  }
}
