import { IpcMain, dialog, shell } from 'electron'
import * as fs from 'fs'

export function setupShellIPC(ipcMain: IpcMain): void {
  // PICK FOLDER
  ipcMain.handle('dialog:pickFolder', async (_e) => {
    const result = await dialog.showOpenDialog({
      properties: ['openDirectory', 'createDirectory'],
    })
    if (result.canceled || result.filePaths.length === 0) return null
    return result.filePaths[0]
  })

  // SHOW IN EXPLORER
  ipcMain.handle(
    'shell:showInExplorer',
    async (_e, { path }: { path: string }) => {
      if (!path || !fs.existsSync(path)) {
        throw new Error('Path does not exist')
      }
      const stat = fs.statSync(path)
      if (stat.isDirectory()) {
        await shell.openPath(path)
      } else {
        shell.showItemInFolder(path)
      }
    }
  )
}
