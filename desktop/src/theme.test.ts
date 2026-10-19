import { describe, it, expect } from "vitest";
import { themeFromValue, readTheme, saveTheme } from "./theme";
describe("appearance", () => {
  it("accepts both themes and falls back from legacy values", () => {
    expect(themeFromValue("light")).toBe("light");
    expect(themeFromValue("dark")).toBe("dark");
    expect(themeFromValue("kpax")).toBe("dark");
  });
  it("restores the saved light theme", () =>
    expect(readTheme({ getItem: () => "light" })).toBe("light"));
  it("persists the chosen theme", () => {
    const saved: Record<string, string> = {};
    saveTheme("light", {
      setItem: (key, value) => {
        saved[key] = value;
      },
    });
    expect(saved["edithub:theme"]).toBe("light");
  });
  it("survives unavailable local storage", () => {
    expect(
      readTheme({
        getItem: () => {
          throw Error("blocked");
        },
      }),
    ).toBe("dark");
    expect(() =>
      saveTheme("light", {
        setItem: () => {
          throw Error("blocked");
        },
      }),
    ).not.toThrow();
  });
});
