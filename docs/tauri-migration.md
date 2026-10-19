# edithub desktop migration

goal: replace the Flutter desktop shell with Tauri 2 + TypeScript + React/Vite, Tailwind, shadcn/Radix, Motion, Zustand and TanStack Query.

- [x] compatible Rust settings and local/iCloud project scanning, project creation, folders, editor launch, recycle bin, archive/restore.
- [x] Rust streamed downloads: Dropbox dl=1 preserving rlkey, Drive confirmation forms, authenticated folder enumeration, cancellation, partial files, ZIP extraction and meaningful failures.
- [x] React project workspace, create/download dialogs, settings, library, accessible interactions and reduced motion.
- [x] run regression tests, TypeScript build, Rust checks and native packaging; document remaining parity gaps honestly.

compatibility: read ~/.edithub/settings.json and google-drive.json, preserve unknown keys, read .edithub.json plus Mac metadata and year/month folders. Do not modify the old applications or user data while building/testing.

design: graphite #181a1e, panel #202329, line #343840, text #eceef2, muted #9ca3b1, lavender #b4a0ff. Segoe UI body/display and Consolas numeric metadata. Narrow project browser, generous central project detail, quiet right-hand folder inspector. Signature: media-bin folder cards with a thin timeline-style accent. Prefer native window chrome and clear controls over glass effects.


verification (2026-10-18):

- rust: 17 passing offline tests, including real local HTTP streams, interrupted transfer + If-Range, cancellation, HTML/403 rejection, ZIP traversal and Flutter/Mac manifests.
- frontend: 4 passing tests; TypeScript and Vite production builds pass.
- native webview: isolated settings, create project, actual download + progress, two archive/restore cycles, file integrity, dialog open/close, settings UI and overflow check pass.
- unsigned Windows NSIS installer built successfully, copied to dist/tauri/EditHub_2.0.0_x64-setup.exe; native screenshots alongside it.
- npm audit: no known vulnerabilities after updating build/test tooling.

limitations: Dropbox user links were not supplied; live OAuth, Resolve scripting/export and cloud upload completion remain unverified. Auto-updates, server catalog sync, batch Resolve export and extra Flutter themes have not been ported. Existing clients and user data were not changed by verification.

follow-up: public Google Drive folder listing now uses embeddedfolderview before OAuth. live check found 293 files across four branches and downloaded a valid 6,014,676-byte JPEG without credentials. full-folder download was not performed. two public-folder parser regression tests added.

live video probe also passed: valid MP4/MOV header in 5,691 received bytes from DRONE; download cancelled deliberately. rebuilt installer copied to dist/tauri.


2026-10-19 / 2.0.1: unified Google credentials reader shared by startup status, refresh, OAuth and downloader. Supports UTF-8 BOM, snake/camel aliases and preserved refresh tokens. Startup verifies the existing session against Drive about API; settings show verified connection or an explicit error with retry. Existing real credentials refreshed successfully and accessed the provided folder through Drive API (HTTP 200). No new keys generated. API-key URLs are stripped from persisted HTTP errors; concurrent credential writes are serialized.

2.0.1 release runtime verified with the actual user profile: configured=true, connected=true, hasApiKey=true; settings UI confirms existing connection on startup. Installer copied to dist/tauri/EditHub_2.0.1_x64-setup.exe. Existing API/OAuth keys still match the original local project secrets; saved access token is valid.
