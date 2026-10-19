import { describe, expect, it, vi } from "vitest";
import { installWhenIdle } from "./updater";

describe("update installation", () => {
  it("checks for running work again after the download", async () => {
    const idle = vi.fn().mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error("Busy"));
    const update = { download: vi.fn().mockResolvedValue(undefined), install: vi.fn() };
    await expect(installWhenIdle(update, idle)).rejects.toThrow("Busy");
    expect(update.download).toHaveBeenCalledOnce();
    expect(update.install).not.toHaveBeenCalled();
  });
  it("restarts after a verified download when idle", async () => {
    const idle = vi.fn().mockResolvedValue(undefined);
    const update = { download: vi.fn().mockResolvedValue(undefined), install: vi.fn().mockResolvedValue(undefined) };
    await installWhenIdle(update, idle);
    expect(idle).toHaveBeenCalledTimes(2);
    expect(idle.mock.calls).toEqual([[false], [true]]);
    expect(update.install).toHaveBeenCalledWith({ restartAfterInstall: true });
  });
});
