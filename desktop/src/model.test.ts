import { describe, it, expect } from "vitest";
import { parseLinks, filterProjects, formatBytes } from "./model";
describe("project workspace", () => {
  it("splits pasted links and removes duplicates", () =>
    expect(
      parseLinks(" https://a.com/f\n\nhttps://b.com/f https://a.com/f "),
    ).toEqual(["https://a.com/f", "https://b.com/f"]));
  it("does not count archived projects as ready", () =>
    expect(
      filterProjects(
        [
          { id: "a", name: "a", status: "archive" },
          { id: "b", name: "b", status: "ready" },
        ] as any,
        "ready",
        "",
      ).map((p) => p.id),
    ).toEqual(["b"]));
  it("searches without case sensitivity", () =>
    expect(
      filterProjects(
        [
          { name: "Клип", status: "ready" },
          { name: "Интервью", status: "ready" },
        ] as any,
        "all",
        "КЛИ",
      ).map((p) => p.name),
    ).toEqual(["Клип"]));
  it("formats file sizes", () => expect(formatBytes(1024 ** 3)).toBe("1.0 GB"));
});
