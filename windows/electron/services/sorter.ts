import * as fs from 'fs'
import * as path from 'path'

const AUDIO_EXTENSIONS = new Set(['.wav', '.mp3', '.aiff', '.flac', '.ogg', '.aac', '.m4a'])
const IMAGE_EXTENSIONS = new Set(['.png', '.jpg', '.jpeg', '.psd', '.ai', '.svg', '.eps', '.gif', '.webp'])
const DOC_EXTENSIONS = new Set(['.pdf', '.txt', '.doc', '.docx', '.csv', '.xlsx', '.xls'])
const VIDEO_EXTENSIONS = new Set(['.mp4', '.mov', '.mxf', '.avi', '.mkv', '.r3d', '.braw', '.arw', '.dng'])

const VIDEO_KEYWORDS = ['footage', 'raw', 'log', 'braw', 'r3d', 'camera', 'clip']
const MUSIC_KEYWORDS = ['music', 'beat', 'track', 'song', 'melody', 'loop', 'stem']

function getTargetSubfolder(filePath: string): string | null {
  const ext = path.extname(filePath).toLowerCase()
  const name = path.basename(filePath).toLowerCase()

  if (AUDIO_EXTENSIONS.has(ext)) {
    // Check if it sounds like music
    const isMusic = MUSIC_KEYWORDS.some((kw) => name.includes(kw))
    return isMusic ? 'Music' : 'SFX'
  }

  if (IMAGE_EXTENSIONS.has(ext)) {
    return 'Graphics'
  }

  if (DOC_EXTENSIONS.has(ext)) {
    return 'Docs'
  }

  if (VIDEO_EXTENSIONS.has(ext)) {
    // Don't move video files if they look like footage
    const isFootage = VIDEO_KEYWORDS.some((kw) => name.includes(kw))
    if (isFootage) return null // skip
    return 'Footage'
  }

  // Default: SFX for unknown files
  return 'SFX'
}

export function sortFileIntoProject(
  filePath: string,
  projectRoot: string,
  projectId: string,
  onMoved: (from: string, to: string) => void
): void {
  const targetSubfolder = getTargetSubfolder(filePath)
  if (!targetSubfolder) return // Skip (e.g., raw footage)

  const fileName = path.basename(filePath)
  const targetDir = path.join(projectRoot, targetSubfolder)
  const targetPath = path.join(targetDir, fileName)

  // Don't move if already in the right folder
  const currentDir = path.dirname(filePath)
  if (currentDir === targetDir) return

  // Don't move if it's already inside a project subfolder
  const relativePath = path.relative(projectRoot, filePath)
  const parts = relativePath.split(path.sep)
  if (parts.length > 1) return // Already in a subfolder

  try {
    if (!fs.existsSync(targetDir)) {
      fs.mkdirSync(targetDir, { recursive: true })
    }

    // Avoid overwriting
    let finalPath = targetPath
    if (fs.existsSync(targetPath)) {
      const base = path.basename(fileName, path.extname(fileName))
      const ext = path.extname(fileName)
      finalPath = path.join(targetDir, `${base}_${Date.now()}${ext}`)
    }

    fs.renameSync(filePath, finalPath)
    onMoved(filePath, finalPath)
  } catch (err) {
    console.warn(`Failed to sort file ${filePath}:`, err)
  }
}
