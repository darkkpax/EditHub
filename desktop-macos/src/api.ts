import { invoke, isTauri } from "@tauri-apps/api/core";
import type { Project, Settings, Entry } from "./model";
export const native = isTauri();
export interface GoogleStatus {
  configured: boolean;
  connected: boolean;
  hasApiKey: boolean;
}
export function command<T>(
  name: string,
  args?: Record<string, unknown>,
): Promise<T> {
  if (!native) return Promise.reject(new Error("Open the desktop app"));
  return invoke<T>(name, args);
}
export const api = {
  googleStatus: () => command<GoogleStatus>("google_status"),
  settings: () => command<Settings>("get_settings"),
  projects: () => command<Project[]>("list_projects"),
  entries: (id: string, relative = "", folderPath?: string) =>
    command<Entry[]>("project_entries", { id, relative, folderPath }),
  importFiles: (id: string, relative: string, paths: string[]) =>
    command<number>("import_project_files", { id, relative, paths }),
  preview: (id: string, folderPath: string) =>
    command<string | null>("project_preview", { id, folderPath }),
  saveSettings: (settings: Settings) =>
    command<Settings>("save_settings", { settings }),
  setupLibrary: (videosFolder: string) =>
    command<{ settings: Settings; adopted: number }>("setup_library", { videosFolder }),
  create: (name: string, editor: string, urls: string[]) =>
    command<Project>("create_project", { name, editor, urls }),
  download: (id: string, urls: string[]) =>
    command<void>("start_downloads", { id, urls }),
  cancel: (id: string) => command<void>("cancel_downloads", { id }),
  reveal: (id: string, relative = "") =>
    command<void>("reveal_project", { id, relative }),
  open: (id: string) => command<string>("open_project", { id }),
  transfer: (id: string, restore: boolean) =>
    command<void>("transfer_project", { id, restore }),
  archiveInactive: () => command<number>("archive_inactive_projects"),
  remove: (id: string) => command<void>("delete_project", { id }),
};
