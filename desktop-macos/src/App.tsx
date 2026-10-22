import { useEffect, useRef, useState, type ReactNode } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { listen } from "@tauri-apps/api/event";
import { open } from "@tauri-apps/plugin-dialog";
import { getCurrentWindow } from "@tauri-apps/api/window";
import type { UnlistenFn } from "@tauri-apps/api/event";
import { AnimatePresence, motion, useInView } from "motion/react";
import * as Tabs from "@radix-ui/react-tabs";
import {
  Folder,
  FolderOpen,
  Plus,
  Search,
  Settings2,
  Layers3,
  AudioLines,
  ArrowUpRight,
  ArrowDownToLine,
  ChevronRight,
  ChevronLeft,
  RefreshCw,
  Link2,
  Check,
  X,
  Loader2,
  Cloud,
  Film,
  Music2,
  Mic2,
  FileText,
  Image,
  Clapperboard,
  Archive,
  Trash2,
  Play,
  SlidersHorizontal,
  ExternalLink,
  AlertCircle,
  Pause,
  Import,
} from "lucide-react";
import { api, command, native } from "./api";
import { useUI } from "./store";
import {
  filterProjects,
  formatBytes,
  parseLinks,
  type Project,
  type Progress,
  type Settings,
} from "./model";
import { FrostedSelection } from "./components/frosted-selection";
import { ScrollGlass } from "./components/scroll-glass";
import { useAppUpdater } from "./updater";
import { version as appVersion } from "../package.json";
import { Button } from "./components/ui/button";
import { Dialog, DialogContent } from "./components/ui/dialog";

const statusLabels: Record<string, string> = {
  active: "Active",
  ready: "Ready",
  downloading: "Downloading",
  paused: "Paused",
  archive: "Archived",
  incloud: "In cloud",
  uploading: "Uploading",
};
const folderMeta: Record<
  string,
  { label: string; icon: typeof Folder; color: string }
> = {
  FOOTAGE: { label: "Footage", icon: Film, color: "purple" },
  SFX: { label: "Sound effects", icon: AudioLines, color: "blue" },
  MUSIC: { label: "Music", icon: Music2, color: "pink" },
  VOICE: { label: "Voice", icon: Mic2, color: "orange" },
  "READY VIDEOS": {
    label: "Exports",
    icon: Clapperboard,
    color: "green",
  },
  DOCS: { label: "Documents", icon: FileText, color: "blue" },
  GRAPHICS: { label: "Graphics", icon: Image, color: "pink" },
  "B-ROLL": { label: "B-roll", icon: Film, color: "orange" },
  SUBS: { label: "Subtitles", icon: FileText, color: "green" },
};
function date(value: string) {
  const d = new Date(value);
  return Number.isNaN(+d)
    ? "Unknown"
    : d.toLocaleDateString("en-GB", {
        day: "numeric",
        month: "short",
        year: "numeric",
      });
}
const monthNumbers: Record<string, number> = {
  JANUARY: 0, FEBRUARY: 1, MARCH: 2, APRIL: 3, MAY: 4, JUNE: 5,
  JULY: 6, AUGUST: 7, SEPTEMBER: 8, OCTOBER: 9, NOVEMBER: 10, DECEMBER: 11,
};
function monthGroup(project: Project) {
  const created = new Date(project.createdAt);
  if (!Number.isNaN(created.valueOf())) {
    return {
      id: `${created.getFullYear()}-${created.getMonth()}`,
      order: new Date(created.getFullYear(), created.getMonth(), 1).valueOf(),
      label: created.toLocaleDateString("en-GB", { month: "long", year: "numeric" }),
    };
  }
  const month = monthNumbers[(project.month || "").toUpperCase()] ?? Number(project.month) - 1;
  const year = Number(project.year);
  if (Number.isInteger(month) && month >= 0 && month < 12 && Number.isInteger(year)) {
    const value = new Date(year, month, 1);
    return { id: `${year}-${month}`, order: value.valueOf(), label: value.toLocaleDateString("en-GB", { month: "long", year: "numeric" }) };
  }
  return { id: "unknown", order: 0, label: "Earlier projects" };
}
function groupByCreatedMonth(projects: Project[]) {
  const groups = new Map<string, { label: string; order: number; projects: Project[] }>();
  [...projects]
    .sort((a, b) => monthGroup(b).order - monthGroup(a).order || b.createdAt.localeCompare(a.createdAt))
    .forEach((project) => {
      const group = monthGroup(project);
      const current = groups.get(group.id) || { label: group.label, order: group.order, projects: [] };
      current.projects.push(project);
      groups.set(group.id, current);
    });
  return [...groups.entries()].map(([id, group]) => ({ id, ...group }));
}
function ErrorBox({ error }: { error: unknown }) {
  return (
    <div role="alert" className="error-box">
      <AlertCircle size={17} />
      <span>{String(error instanceof Error ? error.message : error)}</span>
    </div>
  );
}
function LibrarySetup({
  onComplete,
}: {
  onComplete: (adopted: number) => void;
}) {
  const [folder, setFolder] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const choose = async () => {
    const selected = await open({ directory: true, multiple: false, title: "Choose your Videos folder" });
    if (typeof selected === "string") setFolder(selected);
  };
  const finish = async () => {
    if (!folder || saving) return;
    setSaving(true);
    setError("");
    try {
      const result = await api.setupLibrary(folder);
      onComplete(result.adopted);
    } catch (e) {
      setError(String(e));
    } finally {
      setSaving(false);
    }
  };
  return (
    <Dialog open>
      <DialogContent title="Welcome to EditHub">
        <p className="muted">Choose the Videos folder created by your previous app. Existing projects will be found and given an EditHub manifest without moving your files.</p>
        <div className="setup-folder">
          <Button variant="outline" onClick={() => void choose()} disabled={saving}>
            <FolderOpen size={17} />
            {folder || "Choose Videos folder"}
          </Button>
          <Button onClick={() => void finish()} disabled={!folder || saving}>
            {saving ? "Preparing library…" : "Use this folder"}
          </Button>
        </div>
        <p className="muted">If iCloud Drive is enabled on this Mac, EditHub also creates its archive folder there.</p>
        {error && <ErrorBox error={error} />}
      </DialogContent>
    </Dialog>
  );
}
function Empty({
  icon: Icon = FolderOpen,
  title,
  children,
}: {
  icon?: typeof Folder;
  title: string;
  children?: ReactNode;
}) {
  return (
    <div className="empty">
      <div className="empty-icon">
        <Icon size={30} strokeWidth={1.3} />
      </div>
      <h2>{title}</h2>
      {children && <div className="empty-content">{children}</div>}
    </div>
  );
}
function ProjectMark({
  project,
  small = false,
}: {
  project: Project;
  small?: boolean;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const visible = useInView(ref, { once: true, margin: "100px" });
  const preview = useQuery({
    queryKey: ["previews", project.id, project.folderPath],
    queryFn: () => api.preview(project.id, project.folderPath),
    enabled: native && visible,
    staleTime: 600_000,
    gcTime: 1_800_000,
    retry: false,
  });
  return (
    <div
      ref={ref}
      className={`project-mark ${small ? "small" : ""} ${preview.data ? "has-preview" : ""}`}
    >
      {preview.data ? (
        <motion.img
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          src={preview.data}
          alt=""
          decoding="async"
        />
      ) : (
        <>
          <span>{project.name.slice(0, 2).toUpperCase()}</span>
          <Film className="mark-film" size={small ? 42 : 90} />
        </>
      )}
    </div>
  );
}
function ThemePicker() {
  const { theme, setTheme } = useUI();
  return (
    <section className="settings-section appearance-section">
      <div className="section-heading">
        <h2>Appearance</h2>
      </div>
      <div className="theme-options" role="group" aria-label="Theme">
        {(["dark", "light"] as const).map((value) => (
          <button
            key={value}
            className={`theme-option ${value} ${theme === value ? "selected" : ""}`}
            aria-pressed={theme === value}
            onClick={() => setTheme(value)}
          >
            <div className="theme-swatch">
              <span>Aa</span>
              <i />
              <i />
            </div>
            <span>
              {value === "dark" ? "Dark" : "Light"}
              {theme === value && (
                <motion.span layoutId="theme-selection" className="theme-check">
                  <Check size={16} />
                </motion.span>
              )}
            </span>
          </button>
        ))}
      </div>
    </section>
  );
}
export default function App() {
  const updater = useAppUpdater();
  const ui = useUI(),
    client = useQueryClient();
  const [createOpen, setCreateOpen] = useState(false);
  useEffect(() => {
    document.documentElement.dataset.theme = ui.theme;
    if (native)
      getCurrentWindow()
        .setTheme(ui.theme)
        .catch(() => {});
  }, [ui.theme]);
  const projects = useQuery({
    queryKey: ["projects"],
    queryFn: api.projects,
    enabled: native,
    refetchInterval: 15000,
  });
  const settings = useQuery({
    queryKey: ["settings"],
    queryFn: api.settings,
    enabled: native,
  });
  useQuery({
    queryKey: ["google-status"],
    queryFn: api.googleStatus,
    enabled: native,
    staleTime: 300000,
    retry: false,
  });
  useEffect(() => {
    if (!native) return;
    let disposed = false;
    let unsubscribe: (() => void) | undefined;
    listen<Progress>("download-progress", (e) => {
      ui.updateProgress(e.payload);
      if (["complete", "error", "cancelled"].includes(e.payload.state)) {
        client.invalidateQueries({ queryKey: ["projects"] });
        client.invalidateQueries({ queryKey: ["entries"] });
        client.invalidateQueries({ queryKey: ["previews"] });
        ui.notify(
          e.payload.state === "complete"
            ? "Downloaded to FOOTAGE"
            : e.payload.error || "Download cancelled",
        );
      }
    }).then((off) => {
      if (disposed) off();
      else unsubscribe = off;
    });
    return () => {
      disposed = true;
      unsubscribe?.();
    };
  }, [client]);
  useEffect(() => {
    if (!ui.notice) return;
    const t = setTimeout(() => ui.notify(null), 6500);
    return () => clearTimeout(t);
  }, [ui.notice]);
  const all = projects.data || [];
  const filtered = filterProjects(all, ui.filter, ui.search);
  const projectGroups = groupByCreatedMonth(filtered);
  const [visibleMonth, setVisibleMonth] = useState("");
  useEffect(() => {
    const viewport = document.querySelector<HTMLElement>(".project-list .scroll-viewport");
    if (!viewport) return;
    const updateMonth = () => {
      const labels = [...viewport.querySelectorAll<HTMLElement>("[data-project-month]")];
      const top = viewport.getBoundingClientRect().top;
      const visible = labels.reduce<HTMLElement | undefined>((current, label) =>
        label.getBoundingClientRect().top <= top + 3 ? label : current, labels[0]);
      setVisibleMonth(visible?.dataset.projectMonth || labels[0]?.dataset.projectMonth || "");
    };
    updateMonth();
    viewport.addEventListener("scroll", updateMonth, { passive: true });
    return () => viewport.removeEventListener("scroll", updateMonth);
  }, [projectGroups]);
  const selected = filtered.find((p) => p.id === ui.selected) || filtered[0];
  useEffect(() => {
    if (native)
      getCurrentWindow()
        .setTitle(
          ui.page === "settings" ? "Settings" : selected?.name || "Projects",
        )
        .catch(() => {});
  }, [ui.page, selected?.name]);
  const running = Object.values(ui.progress).filter(
    (p) => p.state === "downloading",
  );
  return (
    <div className="app-shell">
      <div className="app-body">
        <aside className="project-sidebar">
          <ScrollGlass className="project-list">
            <div className="sidebar-controls">
              <div className="sidebar-title">
                <button
                  className="sidebar-home"
                  aria-label="Projects"
                  onClick={() => ui.setPage("projects")}
                >
                  projects
                </button>
                <button
                  className="icon-button"
                  aria-label="Refresh projects"
                  onClick={() => {
                    projects.refetch();
                    client.invalidateQueries({ queryKey: ["previews"] });
                  }}
                >
                  <RefreshCw
                    size={15}
                    className={projects.isFetching ? "spin" : ""}
                  />
                </button>
              </div>
              <Button
                className="new-project sidebar-create"
                onClick={() => setCreateOpen(true)}
                disabled={!native}
              >
                <Plus size={17} />
                New project
              </Button>
              <div className="filters">
                {[
                  { value: "all", label: "All projects", icon: Layers3 },
                  { value: "ready", label: "Active", icon: Folder },
                  {
                    value: "downloading",
                    label: "Downloads",
                    icon: ArrowDownToLine,
                  },
                  { value: "archive", label: "Archive", icon: Archive },
                ].map(({ value, label, icon: Icon }) => (
                  <motion.button
                    whileHover={{ x: 3 }}
                    whileTap={{ scale: 0.97 }}
                    className={`filter ${ui.filter === value ? "selected" : ""}`}
                    key={value}
                    onClick={() => {
                      ui.setFilter(value);
                      ui.setPage("projects");
                    }}
                  >
                    {ui.filter === value && (
                      <FrostedSelection
                        id="filter-selection"
                        className="filter-highlight"
                      />
                    )}
                    <Icon size={16} />
                    {label}
                    <span>
                      {value === "all"
                        ? all.length
                        : filterProjects(all, value, "").length}
                    </span>
                  </motion.button>
                ))}
              </div>
              <div className="sidebar-projects-heading">
                <span>Projects</span>
                <span>{filtered.length}</span>
              </div>
              <label className="search-field">
                <Search size={15} />
                <input
                  placeholder="Search projects"
                  aria-label="Search projects"
                  value={ui.search}
                  onChange={(e) => ui.setSearch(e.target.value)}
                />
              </label>
              {visibleMonth && <div className="sidebar-month-indicator">{visibleMonth}</div>}
            </div>

            {projects.isLoading ? (
              <div className="loading">
                <Loader2 className="spin" size={20} />
                Loading projects
              </div>
            ) : filtered.length ? (
              projectGroups.map((group) => (
                <section className="project-month-group" key={group.id} data-project-month={group.label}>
                  {group.projects.map((p) => (
                    <motion.button
                  layout="position"
                  whileHover={{ x: 3 }}
                  whileTap={{ scale: 0.97 }}
                  key={p.id}
                  onClick={() => {
                    ui.select(p.id);
                    ui.setPage("projects");
                  }}
                  className={`project-row ${selected?.id === p.id ? "selected" : ""}`}
                >
                  {selected?.id === p.id && (
                    <FrostedSelection
                      id="project-selection"
                      className="project-row-highlight"
                    />
                  )}
                  <ProjectMark project={p} small />
                  <div className="project-row-info">
                    <strong>{p.name}</strong>
                    <span>{statusLabels[p.status] || p.status}</span>
                  </div>
                  <ChevronRight size={13} />
                    </motion.button>
                  ))}
                </section>
              ))
            ) : (
              <p className="sidebar-empty">
                {ui.search ? "No results" : "No projects"}
              </p>
            )}
            <div className="sidebar-bottom">
              <button
                className="sidebar-settings"
                aria-label="Settings"
                aria-current={ui.page === "settings" ? "page" : undefined}
                onClick={() =>
                  ui.setPage(ui.page === "settings" ? "projects" : "settings")
                }
              >
                <Settings2 size={17} />
                <span>Settings</span>
              </button>
            </div>
          </ScrollGlass>
        </aside>
        <div className="content-stage">
          <AnimatePresence initial={false} mode="wait">
            {ui.page === "projects" ? (
              <motion.main
                key="projects"
                className="workspace"
                initial={{ opacity: 0, x: 14 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: -8, transition: { duration: 0.12 } }}
              >
                {projects.error ? (
                  <div className="workspace-padding">
                    <ErrorBox error={projects.error} />
                  </div>
                ) : null}
                {!native ? (
                  <Empty title="Desktop app required">
                    Open the desktop app to access projects.
                  </Empty>
                ) : selected ? (
                  <ProjectDetail key={selected.id} project={selected} />
                ) : (
                  <Empty title="No projects">
                    <Button onClick={() => setCreateOpen(true)}>
                      <Plus size={16} />
                      Create project
                    </Button>
                  </Empty>
                )}
              </motion.main>
            ) : (
              <SettingsScreen
                key="settings"
                settings={settings.data}
                error={settings.error}
                updater={updater}
              />
            )}
          </AnimatePresence>
        </div>
      </div>
      <CreateDialog open={createOpen} onOpenChange={setCreateOpen} />
      {native && settings.isSuccess && settings.data?.onboardingComplete !== true && (
        <LibrarySetup
          onComplete={(adopted) => {
            void client.invalidateQueries({ queryKey: ["settings"] });
            void client.invalidateQueries({ queryKey: ["projects"] });
            ui.notify(adopted ? `Added ${adopted} existing projects` : "Videos folder is ready");
          }}
        />
      )}
      <AnimatePresence>
        {ui.notice && (
          <motion.div
            role="status"
            className="toast"
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 12 }}
          >
            <AlertCircle size={17} />
            <span>{ui.notice}</span>
            <button
              aria-label="Dismiss"
              className="icon-button"
              onClick={() => ui.notify(null)}
            >
              <X size={15} />
            </button>
          </motion.div>
        )}
      </AnimatePresence>
      {running.length > 0 && ui.page !== "projects" && (
        <button
          className="floating-download"
          onClick={() => ui.setPage("projects")}
        >
          <ArrowDownToLine size={16} />
          Downloading: {running.length}
        </button>
      )}
    </div>
  );
}
function ProjectDetail({ project: p }: { project: Project }) {
  const client = useQueryClient(),
    ui = useUI();
  const [relative, setRelative] = useState(""),
    [downloadOpen, setDownloadOpen] = useState(false),
    [action, setAction] = useState<"archive" | "restore" | "delete" | null>(
      null,
    );
  const [detailTab, setDetailTab] = useState("files");
  const [draggingFiles, setDraggingFiles] = useState(false);
  const [importingFiles, setImportingFiles] = useState(false);
  const entries = useQuery({
    queryKey: ["entries", p.id, p.folderPath, relative],
    queryFn: () => api.entries(p.id, relative, p.folderPath),
    staleTime: 30_000,
    gcTime: 600_000,
    refetchOnWindowFocus: false,
  });
  const mutation = useMutation({
    mutationFn: async ({ name }: { name: string }) => {
      if (name === "open") return api.open(p.id);
      if (name === "delete") return api.remove(p.id);
      return api.transfer(p.id, name === "restore");
    },
    onSuccess: (_, args) => {
      client.invalidateQueries({ queryKey: ["projects"] });
      setAction(null);
      ui.notify(
        args.name === "delete"
          ? "Moved to trash"
          : args.name === "archive"
            ? "Moved to iCloud"
            : args.name === "restore"
              ? "Project restored"
              : "Project opened",
      );
    },
    onError: (e) => ui.notify(String(e)),
  });
  const progress = ui.progress[p.id],
    busy = progress?.state === "downloading" || p.status === "downloading",
    archived = p.status === "archive";
  const perform = (fn: () => Promise<unknown>) =>
    fn().catch((e) => ui.notify(String(e)));
  useEffect(() => {
    if (!native) return;
    let unlisten: UnlistenFn | undefined;
    let disposed = false;
    getCurrentWindow().onDragDropEvent(({ payload }) => {
      if (payload.type === "enter" || payload.type === "over") {
        setDraggingFiles(true);
        return;
      }
      if (payload.type === "leave") {
        setDraggingFiles(false);
        return;
      }
      setDraggingFiles(false);
      setImportingFiles(true);
      void api.importFiles(p.id, relative, payload.paths)
        .then((count) => {
          client.invalidateQueries({ queryKey: ["entries", p.id] });
          client.invalidateQueries({ queryKey: ["previews", p.id] });
          ui.notify(`${count} ${count === 1 ? "file" : "files"} copied to ${relative || "project root"}`);
        })
        .catch((error) => ui.notify(String(error)))
        .finally(() => setImportingFiles(false));
    }).then((stop) => {
      if (disposed) stop();
      else unlisten = stop;
    });
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, [client, p.id, relative, ui.notify]);
  return (
    <motion.div
      className="project-detail"
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
    >
      <ScrollGlass className="project-scroll" resetKey={relative}>
        {(draggingFiles || importingFiles) && (
          <div className="project-drop-target" aria-live="polite">
            <Import size={25} />
            <strong>{importingFiles ? "Copying files…" : "Drop files here"}</strong>
            <span>{relative || "Project root"}</span>
          </div>
        )}
        <section className="project-hero">
          <ProjectMark project={p} />
          <div className="project-summary">
            <div className="project-title-row">
              <h2 className="project-name">{p.name}</h2>
              <details
                className="project-menu"
                onKeyDown={(e) => {
                  if (e.key === "Escape") e.currentTarget.open = false;
                }}
              >
                <summary aria-label="Project actions" title="Project actions">
                  <SlidersHorizontal size={19} />
                </summary>
                <div className="project-menu-content">
                  <button
                    disabled={busy || mutation.isPending}
                    onClick={(e) => {
                      e.currentTarget
                        .closest("details")
                        ?.removeAttribute("open");
                      setAction(archived ? "restore" : "archive");
                    }}
                  >
                    <Archive size={15} />
                    {archived ? "Restore project" : "Move to iCloud"}
                  </button>
                  <button
                    disabled={busy || mutation.isPending}
                    onClick={(e) => {
                      e.currentTarget
                        .closest("details")
                        ?.removeAttribute("open");
                      setAction("delete");
                    }}
                  >
                    <Trash2 size={15} />
                    Move to trash
                  </button>
                </div>
              </details>
            </div>
            <div className="project-meta">
              <span>
                {busy ? "Downloading" : statusLabels[p.status] || p.status}
              </span>
              <span>Created {date(p.createdAt)}</span>
            </div>
          </div>
          <div className="hero-actions">
            <Button
              variant="outline"
              disabled={archived || busy}
              onClick={() => setDownloadOpen(true)}
            >
              <ArrowDownToLine size={16} />
              Download footage
            </Button>
            <Button
              onClick={() => mutation.mutate({ name: "open" })}
              disabled={
                mutation.isPending || archived || p.editor !== "davinci"
              }
            >
              <Play size={15} fill="currentColor" />
              {mutation.isPending && mutation.variables?.name === "open"
                ? "Opening"
                : "Open project"}
              <ArrowUpRight size={15} />
            </Button>
            <Button
              variant="outline"
              onClick={() => perform(() => api.reveal(p.id))}
            >
              <FolderOpen size={16} />
              Show in Explorer
            </Button>
          </div>
        </section>
        <div className="detail-body">
          <div className="detail-primary">
            <Tabs.Root value={detailTab} onValueChange={setDetailTab}>
              <div className="section-tabs">
                <Tabs.List aria-label="Project contents">
                  <Tabs.Trigger value="files">
                    <Folder size={15} />
                    Files
                  </Tabs.Trigger>
                  <Tabs.Trigger value="links">
                    <Link2 size={15} />
                    Sources<span>{p.footageUrls?.length || 0}</span>
                  </Tabs.Trigger>
                </Tabs.List>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => {
                    entries.refetch();
                    client.invalidateQueries({ queryKey: ["previews", p.id] });
                  }}
                  aria-label="Refresh files"
                >
                  <RefreshCw size={15} />
                </Button>
              </div>
              <Tabs.Content value="files" className="tab-content">
                <div className="files-toolbar">
                  <div className="breadcrumb">
                    {relative && (
                      <button
                        className="icon-button"
                        aria-label="Parent folder"
                        onClick={() =>
                          setRelative(
                            relative.split("/").slice(0, -1).join("/"),
                          )
                        }
                      >
                        <ChevronLeft size={16} />
                      </button>
                    )}
                    <span>{relative || "Project root"}</span>
                  </div>
                  <span className="mono">
                    {entries.data?.length || 0} items
                  </span>
                </div>
                {entries.error ? (
                  <ErrorBox error={entries.error} />
                ) : entries.isLoading ? (
                  <div className="loading">
                    <Loader2 size={22} className="spin" />
                  </div>
                ) : entries.data?.length ? (
                  <motion.div
                    key={relative}
                    className="folder-grid"
                    initial={{ opacity: 0, y: 6 }}
                    animate={{ opacity: 1, y: 0 }}
                  >
                    {entries.data.map((e) => {
                      const meta = folderMeta[e.name],
                        Icon = e.isFolder ? meta?.icon || Folder : FileText;
                      return (
                        <motion.button
                          layout="position"
                          whileHover={{ y: -3 }}
                          whileTap={{ scale: 0.97 }}
                          key={e.path}
                          className={`folder-card ${meta?.color || "neutral"}`}
                          onClick={() =>
                            e.isFolder
                              ? setRelative(
                                  [relative, e.name].filter(Boolean).join("/"),
                                )
                              : perform(() =>
                                  api.reveal(
                                    p.id,
                                    [relative, e.name]
                                      .filter(Boolean)
                                      .join("/"),
                                  ),
                                )
                          }
                        >
                          <div className="folder-card-top">
                            <div className="folder-symbol">
                              <Icon size={23} strokeWidth={1.4} />
                            </div>
                            <ArrowUpRight size={14} />
                          </div>
                          <strong>{e.name}</strong>
                          {!e.isFolder && (
                            <span>{formatBytes(e.sizeBytes)}</span>
                          )}
                          <div className="folder-card-line" />
                        </motion.button>
                      );
                    })}
                  </motion.div>
                ) : (
                  <Empty title="Empty folder"></Empty>
                )}
              </Tabs.Content>
              <Tabs.Content value="links" className="tab-content">
                <div className="source-list">
                  {p.footageUrls?.length ? (
                    p.footageUrls.map((url) => (
                      <div key={url}>
                        <Link2 size={17} />
                        <span>{url}</span>
                        <button
                          className="icon-button"
                          aria-label="Copy link"
                          onClick={() =>
                            perform(() => navigator.clipboard.writeText(url))
                          }
                        >
                          <ExternalLink size={15} />
                        </button>
                      </div>
                    ))
                  ) : (
                    <Empty icon={Link2} title="No sources"></Empty>
                  )}
                </div>
              </Tabs.Content>
            </Tabs.Root>
            {progress && progress.state === "downloading" && (
              <div className="download-progress">
                <div>
                  <span className="truncate">{progress.fileName}</span>
                  <span className="mono">
                    {formatBytes(progress.bytesDownloaded)}
                    {progress.totalBytes > 0
                      ? ` / ${formatBytes(progress.totalBytes)}`
                      : ""}
                  </span>
                  <button
                    className="icon-button"
                    aria-label="Cancel download"
                    onClick={() => perform(() => api.cancel(p.id))}
                  >
                    <Pause size={15} />
                  </button>
                </div>
                <progress
                  max={100}
                  value={progress.totalBytes > 0 ? progress.percent : undefined}
                />
              </div>
            )}
            {p.downloadError && !busy && (
              <div className="download-error">
                <ErrorBox error={p.downloadError} />
                {p.footageUrls?.length > 0 && (
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={archived}
                    onClick={() =>
                      perform(() => api.download(p.id, p.footageUrls))
                    }
                  >
                    <RefreshCw size={14} />
                    Retry download
                  </Button>
                )}
              </div>
            )}
          </div>
        </div>
      </ScrollGlass>
      <DownloadDialog
        project={p}
        open={downloadOpen}
        onOpenChange={setDownloadOpen}
      />
      <Dialog
        open={!!action}
        onOpenChange={(value) => {
          if (!value && !mutation.isPending) setAction(null);
        }}
      >
        <DialogContent
          title={
            action === "delete"
              ? "Move to trash?"
              : action === "restore"
                ? "Restore project?"
                : "Move to iCloud?"
          }
          description={
            action === "delete"
              ? "The entire project folder will move to the Recycle Bin"
              : action === "restore"
                ? "Move the project to your local projects folder and remove the cloud copy after copying succeeds"
                : "Export a .drp, copy the project to your iCloud archive, then remove the local copy. iCloud Drive syncs the completed archive."
          }
        >
          <div className="confirm-project">
            <Folder size={19} />
            {p.name}
          </div>
          {mutation.error && <ErrorBox error={mutation.error} />}
          <div className="dialog-actions">
            <Button
              variant="outline"
              disabled={mutation.isPending}
              onClick={() => setAction(null)}
            >
              Cancel
            </Button>
            <Button
              variant={action === "delete" ? "destructive" : "default"}
              disabled={mutation.isPending}
              onClick={() => action && mutation.mutate({ name: action })}
            >
              {mutation.isPending ? (
                <Loader2 size={16} className="spin" />
              ) : null}
              {mutation.isPending
                ? "Working"
                : action === "delete"
                  ? "Move to trash"
                  : action === "restore"
                    ? "Restore"
                    : "Move"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </motion.div>
  );
}
function CreateDialog({
  open: opened,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const client = useQueryClient(),
    ui = useUI();
  const [name, setName] = useState(""),
    [links, setLinks] = useState("");
  const mutation = useMutation({
    mutationFn: async () => {
      const urls = parseLinks(links);
      const project = await api.create(name, "davinci", urls);
      if (urls.length) {
        try {
          await api.download(project.id, urls);
        } catch (e) {
          ui.notify(`Project created; download failed: ${e}`);
        }
      }
      return project;
    },
    onSuccess: (p) => {
      client.invalidateQueries({ queryKey: ["projects"] });
      ui.select(p.id);
      ui.setFilter("all");
      ui.setSearch("");
      onOpenChange(false);
      setName("");
      setLinks("");
    },
  });
  return (
    <Dialog
      open={opened}
      onOpenChange={(v) => {
        if (!mutation.isPending) {
          onOpenChange(v);
          mutation.reset();
        }
      }}
    >
      <DialogContent title="New project">
        <form
          onSubmit={(e) => {
            e.preventDefault();
            mutation.mutate();
          }}
        >
          <label className="field">
            Name
            <input
              autoFocus
              required
              maxLength={120}
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Project name"
            />
          </label>
          <label className="field">
            Source links <span>optional</span>
            <textarea
              rows={3}
              value={links}
              onChange={(e) => setLinks(e.target.value)}
              placeholder="https://drive.google.com/&#10;https://www.dropbox.com/"
            />
          </label>
          {mutation.error && <ErrorBox error={mutation.error} />}
          <div className="dialog-actions">
            <Button
              variant="outline"
              type="button"
              onClick={() => onOpenChange(false)}
              disabled={mutation.isPending}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={!name.trim() || mutation.isPending}>
              {mutation.isPending ? (
                <Loader2 className="spin" size={16} />
              ) : (
                <Plus size={16} />
              )}
              Create project
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
function DownloadDialog({
  project,
  open: opened,
  onOpenChange,
}: {
  project: Project;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const [links, setLinks] = useState("");
  const client = useQueryClient();
  const mutation = useMutation({
    mutationFn: () => api.download(project.id, parseLinks(links)),
    onSuccess: () => {
      onOpenChange(false);
      setLinks("");
      client.invalidateQueries({ queryKey: ["projects"] });
    },
  });
  return (
    <Dialog
      open={opened}
      onOpenChange={(v) => {
        onOpenChange(v);
        mutation.reset();
      }}
    >
      <DialogContent
        title="Download footage"
        description={`${project.name} / FOOTAGE`}
      >
        <form
          onSubmit={(e) => {
            e.preventDefault();
            mutation.mutate();
          }}
        >
          <label className="field">
            Links
            <textarea
              autoFocus
              rows={5}
              placeholder="Google Drive or Dropbox URLs"
              value={links}
              onChange={(e) => setLinks(e.target.value)}
            />
          </label>
          {mutation.error && <ErrorBox error={mutation.error} />}
          <div className="dialog-actions">
            <Button
              type="submit"
              disabled={!links.trim() || mutation.isPending}
            >
              <ArrowDownToLine size={16} />
              Download
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
function SettingsScreen({
  settings,
  error,
  updater,
}: {
  settings: Settings | undefined;
  error: unknown;
  updater: ReturnType<typeof useAppUpdater>;
}) {
  const client = useQueryClient(),
    ui = useUI();
  const [draft, setDraft] = useState<Settings | null>(null),
    [clientId, setClientId] = useState(""),
    [secret, setSecret] = useState(""),
    [apiKey, setApiKey] = useState("");
  const google = useQuery({
    queryKey: ["google-status"],
    queryFn: api.googleStatus,
    enabled: native,
    staleTime: 300000,
    retry: false,
  });
  const [authBusy, setAuthBusy] = useState(false);
  const current = draft || settings;
  const save = useMutation({
    mutationFn: () => api.saveSettings(current!),
    onSuccess: (s) => {
      client.setQueryData(["settings"], s);
      client.invalidateQueries({ queryKey: ["projects"] });
      setDraft(null);
      ui.notify("Settings saved");
    },
  });
  const pick = async (key: string, file = false) => {
    try {
      const result = await open({
        directory: !file,
        multiple: false,
        title: file ? "Choose executable" : "Choose folder",
      });
      if (typeof result === "string" && current)
        setDraft({ ...current, [key]: result });
    } catch (e) {
      ui.notify(String(e));
    }
  };
  const connect = async () => {
    setAuthBusy(true);
    try {
      if (clientId.trim() || secret.trim() || apiKey.trim())
        await command("configure_google", {
          clientId,
          clientSecret: secret,
          apiKey,
        });
      await command("connect_google");
      await google.refetch();
      setSecret("");
      setApiKey("");
      ui.notify("Google Drive connected");
    } catch (e) {
      ui.notify(String(e));
    } finally {
      setAuthBusy(false);
    }
  };
  return (
    <motion.main
      className="settings-screen"
      initial={{ opacity: 0, x: 14 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: -8, transition: { duration: 0.12 } }}
    >
      <header className="workspace-header settings-navigation">
        <Button
          variant="ghost"
          size="sm"
          aria-label="Back to projects"
          onClick={() => ui.setPage("projects")}
        >
          <ChevronLeft size={17} />
          Back to projects
        </Button>
      </header>
      <div className="settings-scroll">
        <div className="page-heading">
          <h1>settings</h1>
        </div>
        {Boolean(error) && <ErrorBox error={error} />}
        <ThemePicker />
        <section className="settings-section">
          <h2>EditHub</h2>
          <p>{appVersion} — {updater.status}</p>
          <Button variant="outline" disabled={!native || updater.busy} onClick={() => void updater.checkNow()}>
            Check for updates
          </Button>
          {updater.version && <Button disabled={updater.busy} onClick={() => void updater.install()}>Install and restart</Button>}
        </section>
        {current ? (
          <>
            <section className="settings-section">
              <h2>
                <Folder size={18} />
                Folders
              </h2>
              {[
                ["projectsFolder", "Projects"],
                ["icloudPath", "iCloud Drive"],
                ["downloadsFolder", "Downloads"],
              ].map(([key, label]) => (
                <label className="path-field" key={key}>
                  <span>{label}</span>
                  <div>
                    <input
                      value={String(current[key] || "")}
                      onChange={(e) =>
                        setDraft({ ...current, [key]: e.target.value })
                      }
                    />
                    <Button
                      variant="outline"
                      size="icon"
                      aria-label={`Choose ${label}`}
                      onClick={() => pick(key)}
                    >
                      <FolderOpen size={16} />
                    </Button>
                  </div>
                </label>
              ))}
            </section>
            <section className="settings-section">
              <h2>
                <Clapperboard size={18} />
                Editor
              </h2>
              {[["davinciPath", "Application path"]].map(([key, label]) => (
                <label className="path-field" key={key}>
                  <span>{label}</span>
                  <div>
                    <input
                      value={String(current[key] || "")}
                      onChange={(e) =>
                        setDraft({ ...current, [key]: e.target.value })
                      }
                    />
                    <Button
                      variant="outline"
                      size="icon"
                      aria-label={`Choose ${label}`}
                      onClick={() => pick(key, true)}
                    >
                      <FolderOpen size={16} />
                    </Button>
                  </div>
                </label>
              ))}
            </section>
            {save.error && <ErrorBox error={save.error} />}
            <div className="save-settings">
              <Button
                disabled={save.isPending || !draft}
                onClick={() => save.mutate()}
              >
                <Check size={16} />
                {save.isPending ? "Saving" : "Save settings"}
              </Button>
            </div>
          </>
        ) : (
          !error && (
            <p className="muted">
              {native
                ? "Loading settings"
                : "Open the desktop app to change settings"}
            </p>
          )
        )}
        <section className="settings-section google-section">
          <div className="service-header">
            <div className="service-logo">
              <Cloud size={23} />
            </div>
            <div>
              <h2>google drive</h2>
              <p>
                {google.isFetching
                  ? "Checking"
                  : google.data?.connected
                    ? "Connected"
                    : google.data?.hasApiKey
                      ? "API key configured"
                      : "Connect account for private links"}
              </p>
            </div>
          </div>
          {google.error && <ErrorBox error={google.error} />}
          <Button
            variant="outline"
            disabled={!native || google.isFetching || authBusy}
            onClick={() => google.refetch()}
          >
            <RefreshCw size={16} className={google.isFetching ? "spin" : ""} />
            Check connection
          </Button>
          <details>
            <summary>Credentials</summary>
            <label className="field">
              OAuth client ID
              <input
                value={clientId}
                onChange={(e) => setClientId(e.target.value)}
                placeholder={
                  google.data?.configured
                    ? "Configured"
                    : "apps.googleusercontent.com"
                }
              />
            </label>
            <label className="field">
              client secret
              <input
                type="password"
                autoComplete="off"
                value={secret}
                onChange={(e) => setSecret(e.target.value)}
                placeholder="Unchanged if empty"
              />
            </label>
            <label className="field">
              API key <span>optional</span>
              <input
                type="password"
                autoComplete="off"
                value={apiKey}
                onChange={(e) => setApiKey(e.target.value)}
              />
            </label>
            <Button
              variant="outline"
              disabled={!native || authBusy || !apiKey.trim()}
              onClick={async () => {
                try {
                  await command("configure_google", {
                    clientId,
                    clientSecret: secret,
                    apiKey,
                  });
                  setSecret("");
                  setApiKey("");
                  await google.refetch();
                  ui.notify("Credentials saved");
                } catch (e) {
                  ui.notify(String(e));
                }
              }}
            >
              Save credentials
            </Button>
          </details>
          <Button
            variant="outline"
            disabled={!native || authBusy}
            onClick={connect}
          >
            {authBusy ? (
              <Loader2 size={16} className="spin" />
            ) : (
              <ExternalLink size={16} />
            )}
            {authBusy
              ? "Complete sign-in in your browser"
              : google.data?.connected
                ? "Reconnect"
                : "Connect account"}
          </Button>
        </section>
        <section className="settings-section">
          <div className="service-header">
            <div className="service-logo dropbox-logo">
              <Layers3 size={23} />
            </div>
            <div>
              <h2>dropbox</h2>
              <p>Public links</p>
            </div>
          </div>
        </section>
      </div>
    </motion.main>
  );
}
