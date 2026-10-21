export interface Project {
  id: string;
  name: string;
  year?: string;
  month?: string;
  createdAt: string;
  lastOpenedAt: string;
  footageUrls: string[];
  status: string;
  editor: string;
  folderPath: string;
  downloadError?: string;
}
export interface Entry {
  name: string;
  path: string;
  isFolder: boolean;
  sizeBytes: number;
}
export interface Settings {
  projectsFolder: string;
  downloadsFolder: string;
  icloudPath: string;
  davinciPath: string;
  [key: string]: unknown;
}
export interface Progress {
  projectId: string;
  fileUrl: string;
  fileName: string;
  bytesDownloaded: number;
  totalBytes: number;
  percent: number;
  state: string;
  error?: string;
}
export function parseLinks(value: string): string[] {
  return [...new Set(value.trim().split(/\s+/).filter(Boolean))];
}
export function filterProjects(
  projects: Project[],
  filter: string,
  search: string,
): Project[] {
  return projects.filter(
    (p) =>
      (filter === "all" ||
        (filter === "ready"
          ? ["ready", "active", "paused"].includes(p.status)
          : p.status === filter)) &&
      p.name.toLocaleLowerCase().includes(search.toLocaleLowerCase()),
  );
}
export function formatBytes(bytes: number): string {
  if (!bytes) return "0 B";
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), 4);
  return `${(bytes / 1024 ** i).toFixed(i ? 1 : 0)} ${["B", "KB", "MB", "GB", "TB"][i]}`;
}
