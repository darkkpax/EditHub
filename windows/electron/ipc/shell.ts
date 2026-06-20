import { IpcMain, dialog, shell } from 'electron'

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
      shell.showItemInFolder(path)
    }
  )
}
