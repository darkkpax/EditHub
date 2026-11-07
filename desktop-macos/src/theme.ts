import type { HeadingFont } from "./model";
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

const HEADING_FONT_KEY = "edithub:headingFont";

export function readHeadingFont(storage?: Pick<Storage, "getItem">): HeadingFont | null {
  try {
    const value = (storage ?? window.localStorage).getItem(HEADING_FONT_KEY);
    switch (value) {
      case "system":
      case "rounded":
      case "serif":
      case "cinematic":
      case "gothic":
        return value;
    }
  } catch {
    // Use the saved app settings or default when storage is unavailable.
  }
  return null;
}

export function saveHeadingFont(font: HeadingFont, storage?: Pick<Storage, "setItem">): void {
  try {
    (storage ?? window.localStorage).setItem(HEADING_FONT_KEY, font);
  } catch {
    // The font still applies until the app closes.
  }
}
