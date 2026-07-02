# EditHub — Flutter migration

Replacing the Electron (`windows/`) app with a native Flutter Windows app. Both
UI and backend are rewritten in Dart; the old Node services are the reference
spec, not a runtime dependency.

## Compatibility contract (must match the Electron app)
- Settings file: `~/.edithub/settings.json` — **same path and JSON keys**, so an
  existing install keeps its config. Keys: `projectsFolder`, `downloadsFolder`,
  `dropfxLibrary`, `davinciPath`, `autoArchiveDays`, `autoImportPatterns`,
  `icloudPath`.
- Project manifest: `.edithub.json` inside each project folder (same shape as
  `ProjectInfo`).
- Folder layout: `{projectsFolder}/{YEAR}/{MONTH}/{Project}/` with subfolders
  FOOTAGE, SFX, MUSIC, READY VIDEOS, MISC, VOICE/ENCHANCE, VOICE/NOT ENCHANCE,
  DOCS, GRAPHICS, B-ROLL, SUBS.
- Archive root: `{icloudPath}/Videos/{YEAR}/{MONTH}/` (single source of truth).

## Dart mapping of Electron services
| Electron (`windows/electron/services`) | Dart (`flutter_app/lib/services`) |
|---|---|
| settings-store.ts | settings_service.dart |
| project-store.ts  | project_store.dart |
| archiver.ts       | archiver_service.dart |
| icloud.ts         | icloud_service.dart |
| watcher.ts        | watcher_service.dart |
| davinci.ts        | davinci_service.dart |
| downloader.ts     | downloader_service.dart |

External-process logic (DaVinci launch, `attrib`, registry query for the iCloud
path) uses `dart:io` `Process.run`. Zip extraction uses the `archive` package
instead of `Expand-Archive`/adm-zip.

## UI
- Frameless dark window via `window_manager`; tray via `tray_manager`.
- Theme tokens ported from `windows/src/styles/theme.css`
  (bg `#1c1c1e`, card `#2c2c2e`, accent `#2f8cff`, etc.) into `theme.dart`.
- State via Riverpod. Screens: Projects, Settings, Onboarding, DropFX.
- Icon-only tabs, no bottom status bar, "Сгрузить" for archive (per user prefs).

## Launch + auto-update
- `flutter build windows` → native `.exe` (no Vite/Node/console).
- Auto-update via `auto_updater` (WinSparkle) reading an `appcast.xml` published
  to GitHub Releases by the same tag-triggered GitHub Action.

## Status
Implemented in Flutter: models, compatible settings/project manifests, project
scanning, two-pane Projects UI, project creation, background public-link
downloads with progress/resume/ZIP extraction, silent authorization config
from `iCloud Drive/EditHub/auth.json` (no login screen), Settings,
archiver/iCloud primitives, and DaVinci launch primitives.

Desktop parity pass: the window is fixed to a `1152 × 760` minimum, project
sizes are calculated from disk, project/folder reveal actions use Explorer,
the DaVinci bridge is bundled as a Flutter asset, and the Projects shell uses
JumperCut-derived live glass, anchored overlays, and motion primitives.

Remaining migration work: Downloads-folder watcher and auto-import prompt,
DropFX UI/backend, first-run folder onboarding, tray integration, packaging,
and auto-update wiring.
