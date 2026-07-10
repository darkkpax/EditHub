import { app } from 'electron'
import * as fs from 'fs'
import * as path from 'path'

let cachedLogPath: string | null = null

function ensureLogPath(): string {
  if (!cachedLogPath) {
    const dir = path.join(app.getPath('userData'), 'logs')
    fs.mkdirSync(dir, { recursive: true })
    cachedLogPath = path.join(dir, 'edithub.log')
  }
  return cachedLogPath
}

function toText(value: unknown): string {
  if (value instanceof Error) return value.stack || `${value.name}: ${value.message}`
  if (typeof value === 'string') return value
  try {
    return JSON.stringify(value)
  } catch {
    return String(value)
  }
}

export function logLine(
  level: 'INFO' | 'WARN' | 'ERROR',
  message: string,
  details?: unknown
): void {
  const line = `[${new Date().toISOString()}] [${level}] ${message}${details === undefined ? '' : ` ${toText(details)}`}`
  try {
    fs.appendFileSync(ensureLogPath(), `${line}\r\n`, 'utf8')
  } catch {}

  if (level === 'ERROR') {
    console.error(line)
  } else if (level === 'WARN') {
    console.warn(line)
  } else {
    console.log(line)
  }
}

export function getLogPath(): string {
  return ensureLogPath()
}
