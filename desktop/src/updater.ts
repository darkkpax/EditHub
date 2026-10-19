import { check, type Update } from "@tauri-apps/plugin-updater";
import { useCallback, useEffect, useRef, useState } from "react";
import { command, native } from "./api";

export async function installWhenIdle(
  update: Pick<Update, "download" | "install">,
  ensureIdle: (reserve: boolean) => Promise<unknown>,
) {
  await ensureIdle(false);
  await update.download(undefined, { timeout: 300000 });
  await ensureIdle(true);
  await update.install({ restartAfterInstall: true });
}

export function useAppUpdater() {
  const update = useRef<Update | null>(null);
  const locked = useRef(false);
  const mounted = useRef(false);
  const [status, setStatus] = useState("Check for updates");
  const [version, setVersion] = useState("");
  const [busy, setBusy] = useState(false);
  const checkNow = useCallback(async () => {
    if (!native || locked.current) return;
    locked.current = true;
    setBusy(true);
    setStatus("Checking");
    try {
      const found = await check({ timeout: 20000 });
      if (!mounted.current) { await found?.close(); return; }
      await update.current?.close();
      update.current = found;
      setVersion(found?.version || "");
      setStatus(found ? `Version ${found.version} available` : "Up to date");
    } catch {
      if (mounted.current) setStatus("Could not check for updates");
    } finally {
      locked.current = false;
      if (mounted.current) setBusy(false);
    }
  }, []);
  const install = async () => {
    if (locked.current || !update.current) return;
    locked.current = true;
    setBusy(true);
    setStatus("Downloading update");
    try {
      await installWhenIdle(update.current, (reserve) => command("ensure_idle_for_update", { reserve }));
    } catch (e) {
      await command("release_update_install").catch(() => {});
      setStatus(String(e instanceof Error ? e.message : e));
    } finally {
      locked.current = false;
      setBusy(false);
    }
  };
  useEffect(() => {
    mounted.current = true;
    const initial = setTimeout(() => void checkNow(), 5000);
    const timer = setInterval(() => void checkNow(), 6 * 60 * 60 * 1000);
    return () => {
      mounted.current = false;
      clearTimeout(initial);
      clearInterval(timer);
      if (!locked.current) void update.current?.close();
    };
  }, [checkNow]);
  return { status, version, busy, checkNow, install };
}
