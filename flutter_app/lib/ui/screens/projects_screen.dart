import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/new_project_dialog.dart';
import '../widgets/project_detail.dart';
import '../widgets/project_sidebar.dart';
import '../design/motion.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  String? _selectedId;
  final _createLink = LayerLink();
  OverlayEntry? _createEntry;

  // Cache folder listings per project path so a rebuild (e.g. opening the
  // create popup) doesn't re-scan the disk and make the UI stutter.
  final Map<String, Future<List<FolderEntry>>> _folderCache = {};
  // Folder size is walked lazily for the selected project only, off the
  // scan path, and memoized so rebuilds don't recompute it.
  final Map<String, Future<int>> _sizeCache = {};

  @override
  void dispose() {
    _createEntry?.remove();
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
        return Stack(
          children: [
            Row(
              children: [
                ProjectSidebar(
                  projects: projects,
                  selectedId: selected?.id,
                  onSelected: (project) =>
                      setState(() => _selectedId = project.id),
                ),
                Expanded(
                  // Clear the floating top bar (sidebar stays full-height so
                  // its glass reads under the bar).
                  child: Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(.015, 0),
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
                            size: _size(selected),
                            onOpen: () => _open(selected),
                            onReveal: () => _reveal(selected),
                            onArchive: () => _archive(selected),
                            onRestore: () => _restore(selected),
                            onDelete: () => _delete(selected),
                            onEntryOpen: _openEntry,
                            onCancelDownload: () => ref
                                .read(projectRepositoryProvider)
                                .cancelDownload(selected.id),
                          ),
                    ),
                  ),
                ),
              ],
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
      () => Future(() => ref.read(projectStoreProvider).getFolderSizeBytes(folder)),
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
            child: NewProjectPopover(
              onClose: _closeCreate,
              onCreate: _createProject,
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(entry);
    setState(() => _createEntry = entry);
  }

  void _closeCreate() {
    _createEntry?.remove();
    _createEntry = null;
    if (mounted) setState(() {});
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
  }

  Future<void> _open(ProjectInfo project) async {
    final folder = project.folderPath;
    if (folder == null) return;
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
          );
      ref.invalidate(projectsProvider);
      if (mounted) _message('${project.name} offloaded to iCloud.');
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  Future<void> _restore(ProjectInfo project) async {
    final folder = project.folderPath;
    if (folder == null) return;
    try {
      await ref
          .read(archiverServiceProvider)
          .restoreFromArchive(
            folder,
            ref.read(settingsProvider).projectsFolder,
          );
      ref.invalidate(projectsProvider);
      if (mounted) _message('${project.name} restored.');
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  Future<void> _delete(ProjectInfo project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text('The folder "${project.name}" will be deleted from disk.'),
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
