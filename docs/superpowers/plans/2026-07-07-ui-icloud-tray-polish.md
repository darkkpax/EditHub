# UI, iCloud, and Tray Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the project browser compact and expandable, restore all archived iCloud projects under one canonical hierarchy, reopen after updates, and simplify the tray popup.

**Architecture:** Keep the existing Flutter widgets and services. Replace drill-in folder navigation with local expansion state, keep one pinned blur overlay above the scrolling project list, migrate legacy iCloud archive roots into the canonical root before scanning, and use installer restart flags instead of a second updater process.

**Tech Stack:** Flutter/Dart, `dart:io`, Riverpod, `window_manager`, widget/unit tests.

## Global Constraints

- Canonical archive layout is `{icloud}/edithub/Videos/{year}/{MM}/{project}`.
- Existing archived folders must be moved, never deleted.
- No new dependencies.
- Preserve scrolling, keyboard focus, and reduced-motion behavior.

---

### Task 1: Unified pinned header and scrolling project files

**Files:**
- Modify: `flutter_app/lib/ui/screens/projects_screen.dart`
- Modify: `flutter_app/lib/ui/widgets/project_detail.dart`
- Test: `flutter_app/test/projects_screen_test.dart`

**Interfaces:**
- Consumes: `ProjectDetail(size: Future<int>, folders: Future<List<FolderEntry>>)`
- Produces: a single 116px pinned blur and one scrollable file list without a `Project files` label.

- [ ] Write a widget assertion that `Project files` is absent and the file list remains scrollable.
- [ ] Run `flutter test test/projects_screen_test.dart` and verify it fails on the label.
- [ ] Remove the mini-header, keep the common blur overlay pinned, and align the larger project icon/name inside the top bar.
- [ ] Run the focused test and verify it passes.

### Task 2: Inline expandable folders

**Files:**
- Modify: `flutter_app/lib/ui/widgets/project_detail.dart`
- Test: `flutter_app/test/project_detail_test.dart`

**Interfaces:**
- Consumes: recursive `FolderEntry.children`.
- Produces: inline `AnimatedSize` expansion; files call the existing `onEntryOpen` callback.

- [ ] Change the existing folder test to expect `clip.mp4` below `FOOTAGE` while the root folders remain visible.
- [ ] Run the focused test and verify the old drill-in behavior fails.
- [ ] Replace breadcrumb navigation with a set of expanded folder paths and recursively rendered compact rows.
- [ ] Run the focused test and verify expansion and file opening pass.

### Task 3: Canonical iCloud archive discovery and migration

**Files:**
- Modify: `flutter_app/lib/services/icloud_service.dart`
- Modify: `flutter_app/lib/services/project_store.dart`
- Modify: `flutter_app/lib/state/providers.dart`
- Test: `flutter_app/test/project_store_backend_test.dart`

**Interfaces:**
- Consumes: legacy roots `{icloud}/Videos` and `{icloud}/EditHub/Videos`.
- Produces: `ICloudService.prepareArchive()` and canonical `{icloud}/edithub/Videos/{year}/{MM}` scanning.

- [ ] Add a filesystem test with projects in both legacy roots and month names.
- [ ] Run the test and verify legacy projects are missing.
- [ ] Move projects into the canonical root, normalize months to `01` through `12`, and scan the result.
- [ ] Run the filesystem test and verify every archived project is returned once.

### Task 4: Update restart and compact tray

**Files:**
- Modify: `flutter_app/lib/services/updater_service.dart`
- Modify: `flutter_app/lib/ui/app.dart`
- Test: `flutter_app/test/updater_version_test.dart`
- Test: `flutter_app/test/app_without_login_test.dart`

**Interfaces:**
- Produces: installer arguments `/VERYSILENT /NORESTART /RESTARTAPPLICATIONS`; a 176x72 opaque tray menu; immediate `exit(0)` after tray cleanup.

- [ ] Add assertions for restart installer arguments and the compact tray surface.
- [ ] Run focused tests and verify they fail.
- [ ] Centralize installer arguments, replace tray glass with an opaque rounded `Material`, and avoid waiting on window destruction when quitting.
- [ ] Run focused tests and verify they pass.

### Task 5: Verify and release

**Files:**
- Modify: `flutter_app/pubspec.yaml`

- [ ] Run `flutter analyze` and expect no issues.
- [ ] Run `flutter test` and expect all tests to pass.
- [ ] Run `flutter build windows --release` and expect `edithub.exe`.
- [ ] Bump the patch version, commit only scoped files, tag, and push `master` plus the tag.
