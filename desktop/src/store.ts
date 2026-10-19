import { create } from "zustand";
import { readTheme, saveTheme, type Theme } from "./theme";
import type { Progress } from "./model";
interface UIState {
  theme: Theme;
  setTheme: (theme: Theme) => void;
  page: "projects" | "settings";
  selected: string | null;
  filter: string;
  search: string;
  progress: Record<string, Progress>;
  notice: string | null;
  setPage: (page: UIState["page"]) => void;
  select: (id: string | null) => void;
  setFilter: (filter: string) => void;
  setSearch: (search: string) => void;
  updateProgress: (p: Progress) => void;
  notify: (notice: string | null) => void;
}
export const useUI = create<UIState>((set) => ({
  theme: readTheme(),
  setTheme: (theme) => {
    saveTheme(theme);
    set({ theme });
  },
  page: "projects",
  selected: null,
  filter: "all",
  search: "",
  progress: {},
  notice: null,
  setPage: (page) => set({ page }),
  select: (selected) => set({ selected }),
  setFilter: (filter) => set({ filter }),
  setSearch: (search) => set({ search }),
  updateProgress: (p) =>
    set((s) => ({ progress: { ...s.progress, [p.projectId]: p } })),
  notify: (notice) => set({ notice }),
}));
