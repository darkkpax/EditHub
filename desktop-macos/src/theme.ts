export type Theme = "dark" | "light";
// New preference key makes the macOS edition start in its intended light mode
// without overwriting a theme chosen afterwards by the user.
export const THEME_KEY = "edithub:theme:macos-v1";
export function themeFromValue(value: unknown): Theme {
  return value === "dark" ? "dark" : "light";
}
export function readTheme(storage?: Pick<Storage, "getItem">): Theme {
  try {
    return themeFromValue((storage ?? window.localStorage).getItem(THEME_KEY));
  } catch {
    return "light";
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
