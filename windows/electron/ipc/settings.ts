import { IpcMain, BrowserWindow } from 'electron'
import { loadSettings, updateSettings, Settings } from '../services/settings-store'

export function setupSettingsIPC(
  ipcMain: IpcMain,
  mainWindow: BrowserWindow | null,
  onSettingsChanged: (settings: Settings) => void
): void {
  // GET SETTINGS
  ipcMain.handle('settings:get', async () => {
    return loadSettings()
  })

  // SET SETTINGS
  ipcMain.handle(
    'settings:set',
    async (_e, { settings }: { settings: Partial<Settings> }) => {
      const updated = updateSettings(settings)
      onSettingsChanged(updated)
      return updated
    }
  )

  // Window controls
  ipcMain.handle('window:minimize', (event) => {
    const window = BrowserWindow.fromWebContents(event.sender) || mainWindow
    window?.minimize()
  })

  ipcMain.handle('window:close', (event) => {
    const window = BrowserWindow.fromWebContents(event.sender) || mainWindow
    window?.hide()
  })
}
