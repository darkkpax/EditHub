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

async function downloadInBackground(
  update: Pick<Update, "download">,
  ensureIdle: (reserve: boolean) => Promise<unknown>,
) {
  await ensureIdle(false);
  await update.download(undefined, { timeout: 300000 });
}

export function useAppUpdater() {
  const update = useRef<Update | null>(null);
  const locked = useRef(false);
  const mounted = useRef(false);
  const [status, setStatus] = useState("Check for updates");
  const [version, setVersion] = useState("");
  const [busy, setBusy] = useState(false);
  const [ready, setReady] = useState(false);
  const checkNow = useCallback(async () => {
    if (!native || locked.current) return;
    locked.current = true;
    setBusy(true);
    setStatus("Checking");
    let foundVersion = "";
    try {
      const found = await check({ timeout: 20000 });
      if (!mounted.current) { await found?.close(); return; }
      await update.current?.close();
      update.current = found;
      foundVersion = found?.version || "";
      setVersion(foundVersion);
      setReady(false);
      if (!found) {
        setStatus("Up to date");
        return;
      }

      // Updates are downloaded without interrupting the editor. Installation is
      // deliberately deferred until the user accepts the restart prompt.
      setStatus(`Downloading version ${found.version}`);
      await downloadInBackground(found, (reserve) =>
        command("ensure_idle_for_update", { reserve }),
      );
      if (mounted.current) {
        setReady(true);
        setStatus(`Version ${found.version} is ready to install`);
      }
    } catch {
      if (mounted.current) {
        setStatus(
          foundVersion
            ? `Version ${foundVersion} is available — download will retry later`
            : "Could not check for updates",
        );
      }
    } finally {
      locked.current = false;
      if (mounted.current) setBusy(false);
    }
  }, []);
  const install = async () => {
    if (locked.current || !update.current) return;
    locked.current = true;
    setBusy(true);
    setStatus(ready ? "Installing update" : "Downloading update");
    try {
      if (!ready) {
        await downloadInBackground(update.current, (reserve) =>
          command("ensure_idle_for_update", { reserve }),
        );
        if (mounted.current) setReady(true);
      }
      await command("ensure_idle_for_update", { reserve: true });
      await update.current.install({ restartAfterInstall: true });
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
    const initial = setTimeout(() => void checkNow(), 3000);
    const timer = setInterval(() => void checkNow(), 60 * 60 * 1000);
    return () => {
      mounted.current = false;
      clearTimeout(initial);
      clearInterval(timer);
      if (!locked.current) void update.current?.close();
    };
  }, [checkNow]);
  return { status, version, busy, ready, checkNow, install };
}
