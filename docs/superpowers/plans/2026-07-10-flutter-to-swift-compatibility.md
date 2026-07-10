# Flutter to Swift Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native macOS app recognize the same projects, IDs, footage links, account session, and server catalog as the Flutter Windows app.

**Architecture:** Keep the existing native SwiftUI implementation and add compatibility at its file-format boundaries. Use String project IDs end-to-end, import `.edithub.json` into the existing metadata model, and seed Keychain/server URL from the shared iCloud `auth.json` when no local session exists.

**Tech Stack:** Swift 6, SwiftUI, Foundation, Security, existing EditHub HTTP API.

## Global Constraints

- Preserve `.edithub.json`, `~/.edithub/settings.json`, and server API compatibility.
- Do not add dependencies or duplicate existing Swift services.
- Never overwrite newer native metadata with empty legacy values.

---

### Task 1: Cross-platform project identity and manifest import

**Files:**
- Modify: `Sources/EditHub/Models/Project.swift`
- Modify: `Sources/EditHub/Core/ProjectMetadata.swift`
- Modify: `Sources/EditHub/Core/ProjectManifest.swift`
- Modify: `Sources/EditHub/Models/ProjectStore.swift`
- Modify: `Sources/EditHub/Views/CreateAndDownloadPopover.swift`
- Modify: `Sources/EditHub/Views/ProjectDetailView.swift`
- Test: `Tests/EditHubTests/ProjectCompatibilityTests.swift`

**Interfaces:**
- Consumes: Flutter `.edithub.json` fields `id`, `footageUrls`, `createdAt`, `lastOpenedAt`, `status`, `editor`.
- Produces: `Project.id: String` and persisted `.edithub-metadata.json` with the same ID.

- [ ] Write a test that loads a Flutter manifest with a non-UUID string ID.
- [ ] Verify it fails with the current UUID-only decoder.
- [ ] Change project/metadata/archive IDs to strings and import `.edithub.json` during scanning.
- [ ] Verify server payloads use the unchanged string ID.

### Task 2: Shared iCloud account bootstrap

**Files:**
- Modify: `Sources/EditHub/Core/AuthStore.swift`
- Test: `Tests/EditHubTests/AuthImportTests.swift`

**Interfaces:**
- Consumes: `~/Library/Mobile Documents/com~apple~CloudDocs/EditHub/auth.json`.
- Produces: Keychain JWT plus `NetworkClient.serverURL` on first macOS launch.

- [ ] Write a test for Flutter auth JSON decoding and expiration handling.
- [ ] Verify it fails before the importer exists.
- [ ] Import only when Keychain has no valid token; leave login UI as fallback.
- [ ] Verify an expired token is ignored.

### Task 3: Build verification

**Files:**
- Modify: none

**Interfaces:**
- Consumes: repository source.
- Produces: a buildable macOS app ready to open in Xcode.

- [ ] Run `swift test` where the installed SDK supports the declared macOS target.
- [ ] Run `swift build` or the repository macOS build script.
- [ ] Report any host limitation without claiming an unrun macOS build passed.
