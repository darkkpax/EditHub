# EditHub for Windows

Project manager + DropFX sound browser for DaVinci Resolve on Windows 11.

**What it does:**
- Create video projects with auto-folder structure (SFX/ Music/ Footage/ Graphics/ Docs/)
- Download footage from Google Drive / Dropbox links directly into the project
- Auto-sort any file you drop into the project folder to the right subfolder
- Browse your sound library (DropFX), preview sounds, drag into DaVinci — copies to project automatically
- Watch Downloads folder for enhanced audio files (`*-enhanced*`) — toast to copy to project
- Auto-archive old projects to iCloud Drive, restore with one click
- Config syncs across computers via iCloud

---

## Quick start (dev)

### Requirements

| Tool | Install |
|------|---------|
| Node.js 20+ | https://nodejs.org |
| Python 3.11+ | https://www.python.org/downloads/ (check "Add to PATH") |

Python is only needed in dev mode. The installed app includes a bundled backend — no Python required.

### Run in dev mode

```bat
git clone https://github.com/worldkpax/EditHubWin
cd EditHubWin
npm install
npm run dev
```

The app opens automatically. On first launch you'll see the setup screen — point it to your projects folder and DaVinci Resolve.

### Build installer (.exe)

```bat
npm run dist:win
```

Outputs `dist\EditHub Setup x.x.x.exe` — one-click installer, no Python needed.

> **Before building:** run `pyinstaller assets/dropfx_backend.spec --distpath assets/ --workpath build/pyinstaller` from the `assets/` folder to bundle the Python backend. Skip this if you don't have PyInstaller — the app will try to use system Python instead and show DropFX as unavailable if Python isn't installed.

---

## iCloud sync

Settings are stored in `iCloud Drive\EditHub\config.json` and sync automatically across all your Windows and Mac machines running EditHub.

Make sure **iCloud for Windows** is installed and signed in: https://support.apple.com/en-us/103232

---

## Project folder structure

```
D:\Projects\
└── MyVideo\
    ├── MyVideo.drp       ← DaVinci project file
    ├── SFX\              ← sound effects
    ├── Music\            ← music tracks
    ├── Footage\          ← downloaded footage
    ├── Graphics\         ← images, logos
    ├── Docs\             ← scripts, notes
    └── .edithub.json     ← project metadata
```

Files dropped into the project root are auto-sorted. Footage files (`.mp4`, `.mov`, `.braw`, etc.) are never moved automatically.

---

## DropFX — sound browser

DropFX indexes your sound library folder (set in Settings). Hover any sound to preview it. Drag it — the file is copied to the active project's `SFX/` folder instantly.

The DropFX backend (`dropfx_backend.exe` or `dropfx_backend.py`) runs locally on port 8765.
