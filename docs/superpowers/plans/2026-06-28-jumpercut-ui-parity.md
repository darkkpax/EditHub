# JumperCut UI Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring EditHub's Flutter window, glass UI, popup behavior, motion, folder actions, and project metadata to the quality and interaction model of the local JumperCut Flutter app.

**Architecture:** Reuse the proven JumperCut patterns as small shared design widgets (`GlassSurface`, `PressableScale`, `FadeInUp`) and keep Windows shell operations in a service. Project scanning remains the source of truth for disk size and folder entries; the UI only renders those results and dispatches commands.

**Tech Stack:** Flutter 3.44, Dart 3.12, Riverpod 3, `window_manager`, `dart:ui` BackdropFilter, `dart:io` process/filesystem services.

## Global Constraints

- Initial and minimum window size are both `1152 × 760`; the window may grow but not shrink.
- The create control is an anchored `OverlayEntry`, never a modal `Dialog`.
- Blur must sample live Flutter content behind it; never wrap a BackdropFilter in Opacity.
- Folder/file shell actions run outside widgets through `ShellService`.
- Existing Electron-compatible settings and manifest formats remain unchanged.

---

### Task 1: Lock the desktop window floor

**Files:**
- Create: `flutter_app/lib/window_config.dart`
- Modify: `flutter_app/lib/main.dart`
- Test: `flutter_app/test/window_config_test.dart`

**Interfaces:**
- Produces: `kEditHubWindowSize` and `kEditHubMinimumSize`, both `Size(1152, 760)`.

- [ ] Write a failing test asserting both constants equal `const Size(1152, 760)`.
- [ ] Run `flutter test test/window_config_test.dart`; expect missing constants.
- [ ] Define the constants and use them in `WindowOptions.size` and `minimumSize`.
- [ ] Re-run the test; expect PASS.

### Task 2: Restore backend metadata and shell actions

**Files:**
- Create: `flutter_app/lib/services/shell_service.dart`
- Modify: `flutter_app/lib/services/project_store.dart`
- Modify: `flutter_app/lib/state/providers.dart`
- Test: `flutter_app/test/project_store_backend_test.dart`

**Interfaces:**
- Produces: `ShellService.openPath(String path, {bool selectFile = false})` and scanned `ProjectInfo.sizeBytes`.

- [ ] Write failing tests that scan a temporary project containing a known-size file and assert `sizeBytes`, plus assert Explorer arguments for opening a folder and selecting a file.
- [ ] Run the focused test; expect missing size/launcher behavior.
- [ ] Populate `sizeBytes` when pushing scanned projects and implement detached Explorer launch.
- [ ] Re-run the focused test; expect PASS.

### Task 3: Port JumperCut glass and motion primitives

**Files:**
- Create: `flutter_app/lib/ui/design/glass_surface.dart`
- Create: `flutter_app/lib/ui/design/motion.dart`
- Test: `flutter_app/test/design_primitives_test.dart`

**Interfaces:**
- Produces: `GlassSurface`, `PressableScale`, and `FadeInUp` matching the local JumperCut implementations.

- [ ] Write widget tests asserting the glass contains `BackdropFilter` and press feedback changes scale.
- [ ] Run the focused test; expect missing widgets.
- [ ] Port the minimal proven implementations with EditHub colors/radii.
- [ ] Re-run the focused test; expect PASS.

### Task 4: Replace the create dialog with an anchored popup

**Files:**
- Replace: `flutter_app/lib/ui/widgets/new_project_dialog.dart`
- Modify: `flutter_app/lib/ui/screens/projects_screen.dart`
- Modify: `flutter_app/test/projects_screen_test.dart`

**Interfaces:**
- Produces: `NewProjectPopover`, attached to the FAB through `LayerLink`, with glass blur and spring scale entrance.

- [ ] Change the existing widget test to require a keyed popup, a `BackdropFilter`, and no `Dialog` after tapping the plus button.
- [ ] Run it; expect failure against the modal implementation.
- [ ] Insert/remove an `OverlayEntry` with an outside-tap dismiss layer and `CompositedTransformFollower` opening above the FAB.
- [ ] Re-run the widget test; expect PASS.

### Task 5: Apply blur, icons, motion, and open actions to project UI

**Files:**
- Modify: `flutter_app/lib/ui/widgets/project_sidebar.dart`
- Modify: `flutter_app/lib/ui/widgets/project_detail.dart`
- Modify: `flutter_app/lib/ui/screens/projects_screen.dart`
- Test: `flutter_app/test/project_detail_test.dart`

**Interfaces:**
- Consumes: `GlassSurface`, `PressableScale`, `FadeInUp`, and `ShellService`.
- Produces: floating blurred search header, animated project rows/detail transitions, tactile icon buttons, clickable folder/file rows, and non-zero formatted size.

- [ ] Write failing tests that tap a folder row and verify the callback, verify a selected project renders its computed size, and assert the sidebar header contains `BackdropFilter`.
- [ ] Run the focused tests; expect failures.
- [ ] Layer the scrolling list behind a pinned glass search header, stagger rows with `FadeInUp`, animate selection/detail changes, and route row taps through `ShellService`.
- [ ] Re-run the focused tests; expect PASS.

### Task 6: Verify the desktop result

**Files:**
- Modify: `flutter_app/MIGRATION.md`

- [ ] Run `dart format lib test`.
- [ ] Run `dart analyze --fatal-infos`; expect no diagnostics.
- [ ] Run `flutter test`; expect all tests to pass.
- [ ] Run `flutter build windows --debug`; expect `edithub.exe`.
- [ ] Launch the debug executable and verify its initial bounds cannot be resized below `1152 × 760`.
