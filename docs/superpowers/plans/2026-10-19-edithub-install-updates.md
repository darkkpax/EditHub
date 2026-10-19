# EditHub installation and signed updates implementation plan

**Goal:** replace legacy EditHub with the current Tauri client under the EditHub name, publish its source/release to the existing repository and enable signed updates without moving project data.

**Architecture:** keep com.kpax.edithub and ~/.edithub data compatibility; use the official Tauri updater with a dedicated signing key outside the repository and public GitHub release metadata. Check updates automatically, install explicitly when no downloads are active. CI builds, signs and publishes tagged versions. Existing Inno installation is removed only after the new installer is built and verified.

- [x] Inspect GitHub permissions/release access and back up existing settings/credentials locally without printing secrets.
- [x] Rename product to EditHub, add updater plugin/config/public key and a compact update control, preserve all data paths. Verify update state/error tests and frontend/Rust checks.
- [x] Configure release signing secrets and CI publishing of installer, signature and latest.json; audit staged files for generated assets/secrets/unrelated work before committing and pushing.
- [x] Build signed release and publish through the authorized GitHub repository; verify public metadata/artifact signature and completed workflow.
- [x] Stop app, invoke legacy uninstaller, install the prepared replacement, verify registry/shortcuts/data fingerprints and launch installed binary. Confirm update endpoint from the installed version.

Files: desktop/src-tauri/tauri.conf.json, Cargo.toml/lock, capabilities/default.json, src/lib.rs; desktop/package*.json, updater UI/module/tests and App.tsx; .github/workflows/release.yml, project READMEs. Signing private key and recovery backup live outside git; only the public key is committed. Do not stage unrelated LiquidGlass files or local QA/build outputs.

Verified release: v2.3.1, commit 15eabcb
GitHub run 39221349655 completed successfully (checks and signed release)
Public latest.json and installer signatures verified against embedded public key
Installed legacy 1.1.0 was removed; new 2.3.0 installed, then updated through its own UI to 2.3.1 with successful restart
Installed updater check returns no further update, registry reports EditHub 2.3.1, 301 projects and Google connection present
Project metadata and settings preserved; Google access_token/expiresAt renewed normally while client keys and refresh token remained unchanged
Local recovery copy: ~/.edithub-backups/before-tauri-2.3.0
