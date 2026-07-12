import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/dropfx_handoff_service.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/new_project_dialog.dart';
import '../widgets/project_detail.dart';
import '../widgets/project_sidebar.dart';
import '../design/glass_surface.dart';
import '../design/motion.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedId;
  String _query = '';
  // Tells DropFX which project is open (drag-to-SFX target).
  final _dropfxHandoff = DropFXHandoffService();
  String? _handoffWrittenId;
  final _createLink = LayerLink();
  OverlayEntry? _createEntry;
  // Drives the create popover in AND out (fade + scale) so dismissal animates.
  // Built in initState (not `late`) so dispose() never lazily creates a Ticker
  // on a deactivated element.
  late final AnimationController _createAnim;

  // Cache folder listings per project path so a rebuild (e.g. opening the
  // create popup) doesn't re-scan the disk and make the UI stutter.
  final Map<String, Future<List<FolderEntry>>> _folderCache = {};
  // Folder size is walked lazily for the selected project only, off the
  // scan path, and memoized so rebuilds don't recompute it.
  final Map<String, Future<int>> _sizeCache = {};

  @override
  void initState() {
    super.initState();
    _createAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _createEntry?.remove();
    _createAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectsProvider);
    return projectsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(
        error: error.toString(),
        onRetry: () => ref.invalidate(projectsProvider),
      ),
      data: (projects) {
        final selected =
            projects.where((item) => item.id == _selectedId).firstOrNull ??
            projects.firstOrNull;
        // Hand the open project off to DropFX so dragged sounds copy into it.
        if (selected != null && selected.id != _handoffWrittenId) {
          _handoffWrittenId = selected.id;
          _dropfxHandoff.setActive(selected);
        }
        return Stack(
          children: [
            // Bodies flow full-height under the shared glass header.
            Row(
              children: [
                ProjectSidebar(
                  projects: projects,
                  selectedId: selected?.id,
                  onSelected: (project) =>
                      setState(() => _selectedId = project.id),
                  onContextMenu: _showProjectMenu,
                  query: _query,
                ),
                Expanded(
                  // Only the file list animates on project switch — the header
                  // stays put. Springy slide + fade for an iOS-like feel.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: AppCurves.spring,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(.04, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: selected == null
                        ? const _EmptyProjects()
                        : ProjectDetail(
                            key: ValueKey(selected.id),
                            project: selected,
                            folders: _folders(selected),
                            onEntryOpen: _openEntry,
                            onCancelDownload: () => ref
                                .read(projectRepositoryProvider)
                                .cancelDownload(selected.id),
                            onPause: () => ref
                                .read(projectRepositoryProvider)
                                .pauseDownload(selected.id),
                            onResume: () => ref
                                .read(projectRepositoryProvider)
                                .resumeDownload(
                                  selected,
                                  (_) => ref.invalidate(projectsProvider),
                                ),
                          ),
                  ),
                ),
              ],
            ),
            // Single full-width frosted header — one glass surface across the
            // whole top strip, so there's no seam between the search and the
            // project header. The window controls (transparent bar) sit on it.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: GlassSurface(
                blur: 12,
                scrim: .16,
                frost: .05,
                border: false,
                borderRadius: BorderRadius.zero,
                child: SizedBox(
                  height: 116,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 320,
                        child: ProjectSearchField(
                          value: _query,
                          onChanged: (value) =>
                              setState(() => _query = value),
                        ),
                      ),
                      Expanded(
                        child: selected == null
                            ? const SizedBox.shrink()
                            : ProjectHeader(
                                project: selected,
                                size: _size(selected),
                                onOpen: () => _open(selected),
                                onReveal: () => _reveal(selected),
                                onArchive: () => _archive(selected),
                                onRestore: () => _restore(selected),
                                onDelete: () => _delete(selected),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 22,
              bottom: 22,
              child: CompositedTransformTarget(
                link: _createLink,
                child: Tooltip(
                  message: 'New project',
                  child: PressableScale(
                    onTap: _toggleCreate,
                    child: AnimatedRotation(
                      turns: _createEntry == null ? 0 : .125,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutBack,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: .34),
                              blurRadius: 26,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<List<FolderEntry>> _folders(ProjectInfo project) {
    final folder = project.folderPath;
    if (folder == null) return Future.value(const []);
    return _folderCache.putIfAbsent(folder, () async {
      if (!Directory(folder).existsSync()) return const [];
      return ref.read(projectStoreProvider).listProjectFolders(folder);
    });
  }

  Future<int> _size(ProjectInfo project) {
    final folder = project.folderPath;
    if (folder == null) return Future.value(0);
    return _sizeCache.putIfAbsent(
      folder,
      () => Future(
        () => ref.read(projectStoreProvider).getFolderSizeBytes(folder),
      ),
    );
  }

  void _toggleCreate() {
    if (_createEntry != null) {
      _closeCreate();
      return;
    }
    final entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Transparent tap-catcher only — the blur lives on the popover's own
          // GlassSurface, not the whole app behind it.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeCreate,
            ),
          ),
          CompositedTransformFollower(
            link: _createLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.bottomRight,
            offset: const Offset(0, -10),
            child: AnimatedBuilder(
              animation: _createAnim,
              builder: (context, child) {
                final t = Curves.easeOutBack.transform(_createAnim.value);
                return Opacity(
                  opacity: _createAnim.value.clamp(0, 1),
                  child: Transform.scale(
                    scale: .9 + .1 * t,
                    alignment: Alignment.bottomRight,
                    child: child,
                  ),
                );
              },
              child: NewProjectPopover(
                onClose: _closeCreate,
                onCreate: _createProject,
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(entry);
    _createAnim.forward(from: 0);
    setState(() => _createEntry = entry);
  }

  void _closeCreate() {
    final entry = _createEntry;
    if (entry == null) return;
    _createEntry = null;
    if (mounted) setState(() {}); // flip the + rotation back immediately
    _createAnim.reverse().whenComplete(entry.remove);
  }

  Future<void> _createProject(
    String name,
    List<String> urls,
    String editor,
  ) async {
    final project = await ref
        .read(projectRepositoryProvider)
        .create(
          projectsFolder: ref.read(settingsProvider).projectsFolder,
          name: name,
          urls: urls,
          editor: editor,
          session: ref.read(authProvider).value,
          onChanged: (_) => ref.invalidate(projectsProvider),
        );
    if (mounted) setState(() => _selectedId = project.id);
    ref.invalidate(projectsProvider);

    // Auto-create DaVinci project file if using DaVinci editor.
    if (editor == 'davinci' && project.folderPath != null) {
      unawaited(
        ref
            .read(davinciServiceProvider)
            .export(project.folderPath!)
            .catchError((_) {
              // Silently ignore if DaVinci unavailable
              return (exported: false, message: null, drpFilePath: '');
            }),
      );
    }
  }

  Future<void> _open(ProjectInfo project) async {
    final folder = project.folderPath;
    if (folder == null) return;
    if (project.editor == 'premiere') {
      try {
        await ref
            .read(editorServiceProvider)
            .launchPremiere(ref.read(settingsProvider).premierePath, folder);
      } catch (error) {
        if (mounted) _message(error.toString(), error: true);
      }
      return;
    }
    final result = await ref
        .read(davinciServiceProvider)
        .launch(ref.read(settingsProvider).davinciPath, folder);
    if (!result.projectReady && mounted) {
      _message(result.message ?? 'Could not open the project.', error: true);
    }
  }

  Future<void> _reveal(ProjectInfo project) async {
    final folder = project.folderPath;
    if (folder == null) return;
    try {
      await ref.read(shellServiceProvider).openPath(folder);
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  Future<void> _openEntry(FolderEntry entry) async {
    try {
      await ref
          .read(shellServiceProvider)
          .openPath(entry.path, selectFile: !entry.isFolder);
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  Future<void> _archive(ProjectInfo project) async {
    final folder = project.folderPath;
    if (folder == null) return;
    try {
      await ref
          .read(archiverServiceProvider)
          .archiveProject(
            folder,
            ref.read(icloudServiceProvider).archiveFolder,
            sourceRoot: ref.read(settingsProvider).projectsFolder,
          );
      ref.invalidate(projectsProvider);
      if (mounted) _message('${project.name} offloaded to iCloud.');
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  /// Offload keeping FOOTAGE, so the whole project (media included) goes to
  /// iCloud — for when links can't be re-fetched later (bad internet). Exports
  /// the DaVinci project first if Resolve is running, so the .drp travels too.
  Future<void> _archiveWithFootage(ProjectInfo project) async {
    final folder = project.folderPath;
    if (folder == null) return;
    try {
      if (project.editor == 'davinci' &&
          ref.read(davinciServiceProvider).isResolveRunning()) {
        _message('Exporting DaVinci project…');
        await ref.read(davinciServiceProvider).export(folder);
      }
      if (mounted) _message('Offloading ${project.name} with footage…');
      await ref
          .read(archiverServiceProvider)
          .archiveProject(
            folder,
            ref.read(icloudServiceProvider).archiveFolder,
            sourceRoot: ref.read(settingsProvider).projectsFolder,
            keepFootage: true,
          );
      ref.invalidate(projectsProvider);
      if (mounted) {
        _message('${project.name} offloaded to iCloud with footage.');
      }
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  Future<void> _restore(ProjectInfo project) async {
    final folder = project.folderPath;
    if (folder == null) return;
    try {
      final dest = await ref
          .read(archiverServiceProvider)
          .restoreFromArchive(
            folder,
            ref.read(settingsProvider).projectsFolder,
          );
      ref.invalidate(projectsProvider);
      // Offload strips FOOTAGE to save space; re-fetch it from the saved links
      // so restoring on any machine brings the media back too.
      final restored = ref.read(projectStoreProvider).readProjectInfo(dest);
      if (restored != null &&
          restored.footageUrls.isNotEmpty &&
          !_hasFootage(dest)) {
        ref
            .read(projectRepositoryProvider)
            .resumeDownload(
              restored.copyWith(folderPath: dest),
              (_) => ref.invalidate(projectsProvider),
            );
        if (mounted) _message('${project.name} restored — re-downloading footage…');
      } else if (mounted) {
        _message('${project.name} restored.');
      }
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  bool _hasFootage(String projectFolder) {
    final dir = Directory('$projectFolder${Platform.pathSeparator}FOOTAGE');
    return dir.existsSync() &&
        dir.listSync(recursive: true, followLinks: false).whereType<File>().isNotEmpty;
  }

  Future<void> _delete(ProjectInfo project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
          'The folder "${project.name}" will be deleted from disk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.bad),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || project.folderPath == null) return;
    try {
      await Directory(project.folderPath!).delete(recursive: true);
      setState(() => _selectedId = null);
      ref.invalidate(projectsProvider);
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  /// Right-click menu on a project row.
  Future<void> _showProjectMenu(ProjectInfo project, Offset position) async {
    final archived =
        project.status == ProjectStatus.archive ||
        project.status == ProjectStatus.incloud;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      color: AppColors.card2,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: 'open', child: Text(archived ? 'Restore' : 'Open')),
        const PopupMenuItem(value: 'link', child: Text('Add footage link…')),
        if (project.editor == 'davinci')
          const PopupMenuItem(
            value: 'drp',
            child: Text('Export DaVinci project (.drp)'),
          ),
        const PopupMenuItem(value: 'reveal', child: Text('Show in Explorer')),
        if (!archived)
          const PopupMenuItem(value: 'offload', child: Text('Offload to iCloud')),
        if (!archived)
          const PopupMenuItem(
            value: 'offload_footage',
            child: Text('Offload with footage'),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: AppColors.bad)),
        ),
      ],
    );
    if (!mounted) return;
    switch (selected) {
      case 'open':
        archived ? _restore(project) : _open(project);
      case 'link':
        _addLink(project);
      case 'drp':
        _exportDrp(project);
      case 'reveal':
        _reveal(project);
      case 'offload':
        _archive(project);
      case 'offload_footage':
        _archiveWithFootage(project);
      case 'delete':
        _delete(project);
    }
  }

  /// Adds a footage link to an existing project and starts downloading it.
  Future<void> _addLink(ProjectInfo project) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card2,
        title: const Text('Add footage link'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Google Drive / Dropbox / direct URL',
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty || !mounted) return;
    try {
      ref
          .read(projectRepositoryProvider)
          .addFootage(project, [url], (_) => ref.invalidate(projectsProvider));
      setState(() => _selectedId = project.id);
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  Future<void> _exportDrp(ProjectInfo project) async {
    final folder = project.folderPath;
    if (folder == null) return;
    _message('Exporting DaVinci project…');
    final result = await ref.read(davinciServiceProvider).export(folder);
    if (!mounted) return;
    _message(
      result.exported
          ? 'Saved ${result.drpFilePath}'
          : 'Export failed: ${result.message}',
      error: !result.exported,
    );
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.bad : AppColors.card2,
      ),
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.folder_open_rounded, size: 48, color: AppColors.dim),
        SizedBox(height: 12),
        Text('No projects yet', style: TextStyle(fontSize: 17)),
        SizedBox(height: 5),
        Text(
          'Press "+" to create your first project.',
          style: TextStyle(color: AppColors.dim, fontSize: 13),
        ),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(error, style: const TextStyle(color: AppColors.bad)),
        const SizedBox(height: 10),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
