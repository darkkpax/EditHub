# Flutter Core Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the Electron EditHub layout and deliver silent iCloud authorization, project creation, and footage downloading in the Flutter Windows app.

> **Requirement correction (2026-06-28):** Interactive login/register UI is not part of the product. Authorization is provisioned through the Electron-compatible `iCloud Drive/EditHub/auth.json` file and must never block the local application shell.

**Architecture:** Keep filesystem and HTTP operations in services/repositories, expose immutable state through Riverpod notifiers, and keep Flutter widgets focused on presentation. The Electron project screen is the layout contract; the Swift auth client and server API are the account contract.

**Tech Stack:** Flutter 3.44, Dart 3.12, Riverpod 3, package:http, package:archive, Fastify 4, SQLite.

## Global Constraints

- Preserve `~/.edithub/settings.json` keys and the `.edithub.json` manifest format.
- Create projects under `{projectsFolder}/{YEAR}/{MONTH}/{Project}` with the existing folder list.
- Download public Google Drive, Dropbox, and direct HTTP links into `FOOTAGE`.
- Persist auth separately from settings and never put passwords on disk.
- Preserve unrelated user changes in the Electron app and repository.

---

### Task 1: Make server authentication bootable

**Files:**
- Create: `server/src/db/schema.js`
- Modify: `server/src/db/index.js`
- Create: `server/test/auth.test.js`

**Interfaces:**
- Produces: `initializeSchema(db): void` and a database that always has auth/project tables before routes run.

- [ ] Write a failing Node test that opens a temporary database, runs `initializeSchema`, and asserts the `users`, `workspaces`, `workspace_members`, and `projects` tables exist.
- [ ] Run `node --test test/auth.test.js`; expect failure because `schema.js` does not exist.
- [ ] Extract the idempotent schema SQL from `migrate.js` into `initializeSchema` and call it from `db/index.js`.
- [ ] Re-run the Node test; expect PASS.

### Task 2: Add persisted Flutter authentication

**Files:**
- Create: `flutter_app/lib/data/services/auth_api_service.dart`
- Create: `flutter_app/lib/data/services/auth_storage_service.dart`
- Create: `flutter_app/lib/data/repositories/auth_repository.dart`
- Create: `flutter_app/lib/domain/models/auth_session.dart`
- Modify: `flutter_app/lib/state/providers.dart`
- Create: `flutter_app/test/auth_repository_test.dart`

**Interfaces:**
- Produces: `AuthRepository.login`, `register`, `restore`, and `logout`; `AuthSession(token, userId, workspaceId, email, serverUrl)`.

- [ ] Write failing tests using an injected `http.Client` and temporary auth file for successful login, API errors, restore, and logout.
- [ ] Run `flutter test test/auth_repository_test.dart`; expect missing-type failures.
- [ ] Implement typed JSON decoding, explicit non-2xx errors, JWT expiry validation, and atomic session persistence.
- [ ] Register the repository and an `AsyncNotifier<AuthSession?>` in Riverpod.
- [ ] Re-run the focused test; expect PASS.

### Task 3: Add the login/register screen

**Files:**
- Create: `flutter_app/lib/ui/screens/login_screen.dart`
- Modify: `flutter_app/lib/ui/app.dart`
- Create: `flutter_app/test/login_screen_test.dart`

**Interfaces:**
- Consumes: `authProvider` commands from Task 2.
- Produces: login/register form with email, password, optional server URL, loading and API-error states.

- [ ] Write a widget test that verifies labels, validation, mode switching, and submission.
- [ ] Run `flutter test test/login_screen_test.dart`; expect failure because the screen is missing.
- [ ] Build the compact centered form matching `Sources/EditHub/Views/LoginView.swift` and gate the main shell on restored auth.
- [ ] Re-run the widget test; expect PASS.

### Task 4: Implement the download engine

**Files:**
- Create: `flutter_app/lib/services/downloader_service.dart`
- Create: `flutter_app/test/downloader_service_test.dart`

**Interfaces:**
- Produces: `normalizeDownloadUrl`, `filenameFromResponse`, and `DownloaderService.downloadAll` with progress/cancel callbacks.

- [ ] Write failing tests for Google Drive conversion, Dropbox conversion, direct filenames, redirects, streamed writes, progress, and ZIP extraction.
- [ ] Run `flutter test test/downloader_service_test.dart`; expect missing-service failures.
- [ ] Implement streamed HTTP downloads with redirects, bounded retry/backoff, partial-file resume, cancellation, safe filenames, and ZIP extraction into `FOOTAGE`.
- [ ] Re-run the focused test; expect PASS.

### Task 5: Orchestrate local/server project creation

**Files:**
- Create: `flutter_app/lib/data/repositories/project_repository.dart`
- Modify: `flutter_app/lib/services/project_store.dart`
- Modify: `flutter_app/lib/state/providers.dart`
- Create: `flutter_app/test/project_repository_test.dart`

**Interfaces:**
- Produces: `ProjectRepository.create(name, urls)`, which creates folders and a manifest, pushes metadata when authenticated, then starts downloads and persists progress/status.

- [ ] Write failing tests against a temporary project root and local HTTP server.
- [ ] Run `flutter test test/project_repository_test.dart`; expect missing-repository failures.
- [ ] Reject empty/unsafe/duplicate names, create the exact folder tree, write the manifest before networking, sync metadata, and update `downloading`/`ready` state as files arrive.
- [ ] Re-run the focused test; expect PASS.

### Task 6: Restore the two-pane projects UI

**Files:**
- Rewrite: `flutter_app/lib/ui/screens/projects_screen.dart`
- Create: `flutter_app/lib/ui/widgets/new_project_dialog.dart`
- Create: `flutter_app/lib/ui/widgets/project_sidebar.dart`
- Create: `flutter_app/lib/ui/widgets/project_detail.dart`
- Create: `flutter_app/test/projects_screen_test.dart`

**Interfaces:**
- Consumes: `projectsProvider`, `projectRepositoryProvider`, existing archive/DaVinci/filesystem services.
- Produces: 330px searchable sidebar, grouped project rows, selected-project detail, folder tree, status/progress, actions, and bottom-right create button.

- [ ] Write widget tests for selection, empty state, create dialog URL chips, and responsive narrow-window fallback.
- [ ] Run the focused widget test; expect failure against the current grid UI.
- [ ] Port the Electron structure and spacing, keeping the established dark token palette and Russian action copy.
- [ ] Wire create, reveal, DaVinci open, archive, restore, delete, cancel-download, and refresh actions.
- [ ] Re-run the focused test; expect PASS.

### Task 7: Verify the migration slice

**Files:**
- Modify: `flutter_app/MIGRATION.md`

- [ ] Run `dart format lib test`.
- [ ] Run `flutter analyze`; expect no issues.
- [ ] Run `flutter test`; expect all tests to pass.
- [ ] Run `node --test` in `server`; expect all tests to pass.
- [ ] Build `flutter build windows --debug`; expect a successful native Windows build.
- [ ] Mark authentication, project creation, downloader, and projects UI complete in `MIGRATION.md`.
