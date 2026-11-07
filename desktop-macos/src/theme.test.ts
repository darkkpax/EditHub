import { describe, expect, it } from "vitest";
import { readHeadingFont, saveHeadingFont } from "./theme";

describe("heading font", () => {
  it("keeps the chosen font across sessions", () => {
    const entries = new Map<string, string>();
    saveHeadingFont("gothic", { setItem: (key, value) => { entries.set(key, value); } });
    expect(readHeadingFont({ getItem: (key) => entries.get(key) ?? null })).toBe("gothic");
  });

  it("falls back to the saved app settings when no valid local choice exists", () => {
    expect(readHeadingFont({ getItem: () => null })).toBeNull();
    expect(readHeadingFont({ getItem: () => "unsupported" })).toBeNull();
  });
});
