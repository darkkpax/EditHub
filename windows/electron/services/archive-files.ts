import * as fs from 'fs'
import * as path from 'path'

export function removeFootage(projectFolder: string): void {
  for (const entry of fs.readdirSync(projectFolder, { withFileTypes: true })) {
    if (entry.isDirectory() && entry.name.toLowerCase() === 'footage') {
      fs.rmSync(path.join(projectFolder, entry.name), { recursive: true, force: true })
    }
  }
}
