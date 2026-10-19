export type Theme = "dark" | "light";
export const THEME_KEY = "edithub:theme";
export function themeFromValue(value: unknown): Theme {
  return value === "light" ? "light" : "dark";
}
export function readTheme(storage?: Pick<Storage, "getItem">): Theme {
  try {
    return themeFromValue((storage ?? window.localStorage).getItem(THEME_KEY));
  } catch {
    return "dark";
  }
}
export function saveTheme(
  theme: Theme,
  storage?: Pick<Storage, "setItem">,
): void {
  try {
    (storage ?? window.localStorage).setItem(THEME_KEY, theme);
  } catch {
    /* appearance still works when storage is unavailable */
  }
}
