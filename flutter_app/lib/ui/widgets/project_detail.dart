import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme.dart';
import '../design/motion.dart';

class ProjectDetail extends StatelessWidget {
  const ProjectDetail({
    super.key,
    required this.project,
    required this.folders,
    required this.size,
    required this.onOpen,
    required this.onReveal,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
    required this.onCancelDownload,
    required this.onEntryOpen,
  });

  final ProjectInfo project;
  final Future<List<FolderEntry>> folders;
  final Future<int> size;
  final VoidCallback onOpen;
  final VoidCallback onReveal;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final VoidCallback onCancelDownload;
  final ValueChanged<FolderEntry> onEntryOpen;

  @override
  Widget build(BuildContext context) {
    final archived =
        project.status == ProjectStatus.archive ||
        project.status == ProjectStatus.incloud;
    final averageProgress = project.downloadProgress.isEmpty
        ? 0.0
        : project.downloadProgress.values.reduce((a, b) => a + b) /
              project.downloadProgress.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 116,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              key: const Key('project-header'),
              height: 68,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: (archived ? AppColors.warn : AppColors.accent)
                            .withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        archived ? Icons.cloud_outlined : Icons.folder_rounded,
                        color: archived ? AppColors.warn : AppColors.accent,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  project.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 9),
                              _StatusBadge(status: project.status),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                '${_month(project.month)} ${project.year ?? ''}',
                                style: const TextStyle(
                                  color: AppColors.dim,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 12),
                              FutureBuilder<int>(
                                future: size,
                                builder: (_, snap) => Text(
                                  'Size ${snap.hasData ? _formatBytes(snap.data) : '…'}',
                                  style: const TextStyle(
                                    color: AppColors.dim,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _PrimaryAction(
                          key: const Key('project-open-action'),
                          onTap: archived ? onRestore : onOpen,
                          icon: archived
                              ? Icons.cloud_download_rounded
                              : Icons.play_arrow_rounded,
                          label: archived ? 'Restore' : 'Open',
                        ),
                        _CircleAction(
                          key: const Key('project-reveal-action'),
                          tooltip: 'Show in file manager',
                          onTap: onReveal,
                          icon: Icons.folder_open_rounded,
                        ),
                        _CircleAction(
                          key: const Key('project-archive-action'),
                          tooltip: archived
                              ? 'Already in iCloud'
                              : 'Offload to iCloud',
                          onTap: archived ? null : onArchive,
                          icon: Icons.cloud_upload_rounded,
                        ),
                        _CircleAction(
                          key: const Key('project-delete-action'),
                          tooltip: 'Delete project',
                          onTap: onDelete,
                          icon: Icons.delete_outline_rounded,
                          danger: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (project.status == ProjectStatus.downloading)
          Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            decoration: const BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: AppColors.sep),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.downloading_rounded, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Downloading footage · ${averageProgress.round()}%',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: averageProgress / 100),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: onCancelDownload,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Project files',
                  style: TextStyle(
                    color: AppColors.dim,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .7,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: archived
                      ? const _EmptyFolders(
                          text: 'Restore the project to see local files.',
                        )
                      : FutureBuilder<List<FolderEntry>>(
                          future: folders,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final entries = snapshot.data ?? const [];
                            if (entries.isEmpty) {
                              return const _EmptyFolders(
                                text:
                                    'This project folder is empty or unavailable.',
                              );
                            }
                            return _FilesBrowser(
                              root: entries,
                              onOpenFile: onEntryOpen,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _month(String? value) {
    if (value == null || value.isEmpty) return '';
    return '${value[0]}${value.substring(1).toLowerCase()}';
  }

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes == 0) return '0 B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    super.key,
    required this.onTap,
    required this.icon,
    required this.label,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => PressableScale(
    onTap: onTap,
    child: Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 17),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: .25),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: Colors.white),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    super.key,
    required this.tooltip,
    required this.onTap,
    required this.icon,
    this.danger = false,
  });

  final String tooltip;
  final VoidCallback? onTap;
  final IconData icon;
  final bool danger;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: PressableScale(
      onTap: onTap,
      enabled: onTap != null,
      child: AnimatedOpacity(
        opacity: onTap == null ? .35 : 1,
        duration: const Duration(milliseconds: 140),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0x08FFFFFF),
            shape: BoxShape.circle,
            border: Border.all(
              color: danger
                  ? AppColors.bad.withValues(alpha: .55)
                  : Colors.white.withValues(alpha: .45),
            ),
          ),
          child: Icon(
            icon,
            size: 19,
            color: danger ? AppColors.bad : AppColors.txt,
          ),
        ),
      ),
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final ProjectStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ProjectStatus.active => ('Open', AppColors.accent),
      ProjectStatus.downloading => ('Downloading', AppColors.warn),
      ProjectStatus.uploading => ('iCloud', AppColors.brand),
      ProjectStatus.archive ||
      ProjectStatus.incloud => ('iCloud', AppColors.warn),
      ProjectStatus.ready => ('Ready', AppColors.good),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        border: Border.all(color: color.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Recursively counts files (not folders) inside an entry's loaded subtree.
int _fileCount(FolderEntry e) {
  var n = 0;
  for (final c in e.children) {
    n += c.isFolder ? _fileCount(c) : 1;
  }
  return n;
}

/// In-app folder browser: tapping a folder drills into it (never opens
/// Explorer); an empty folder just shakes; a file opens in its default app.
class _FilesBrowser extends StatefulWidget {
  const _FilesBrowser({required this.root, required this.onOpenFile});
  final List<FolderEntry> root;
  final ValueChanged<FolderEntry> onOpenFile;

  @override
  State<_FilesBrowser> createState() => _FilesBrowserState();
}

class _FilesBrowserState extends State<_FilesBrowser> {
  // Breadcrumb of entered folders; empty = project root.
  final List<FolderEntry> _stack = [];

  List<FolderEntry> get _entries =>
      _stack.isEmpty ? widget.root : _stack.last.children;

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_stack.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PressableScale(
              onTap: () => setState(_stack.removeLast),
              child: Row(
                children: [
                  const Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _stack.last.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: entries.isEmpty
              ? const _EmptyFolders(text: 'This folder is empty.')
              : ListView.separated(
                  // Bottom padding clears the floating "+" button so it never
                  // overlaps the last folder rows.
                  padding: const EdgeInsets.only(bottom: 74),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 5),
                  itemBuilder: (_, index) {
                    final entry = entries[index];
                    return FadeInUp(
                      delay: Duration(milliseconds: (index * 22).clamp(0, 220)),
                      child: _FolderTile(
                        entry: entry,
                        fileCount: entry.isFolder ? _fileCount(entry) : 0,
                        onEnter: () => setState(() => _stack.add(entry)),
                        onOpenFile: () => widget.onOpenFile(entry),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FolderTile extends StatefulWidget {
  const _FolderTile({
    required this.entry,
    required this.fileCount,
    required this.onEnter,
    required this.onOpenFile,
  });
  final FolderEntry entry;
  final int fileCount;
  final VoidCallback onEnter;
  final VoidCallback onOpenFile;

  @override
  State<_FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<_FolderTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _onTap() {
    if (!widget.entry.isFolder) {
      widget.onOpenFile();
      return;
    }
    _shake.forward(from: 0); // always give tactile feedback
    if (widget.fileCount > 0) widget.onEnter(); // only drill in if non-empty
  }

  @override
  Widget build(BuildContext context) {
    final isFolder = widget.entry.isFolder;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        // Damped horizontal wobble.
        final dx = _shake.isAnimating
            ? 8 * (1 - _shake.value) * math.sin(_shake.value * math.pi * 4)
            : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: PressableScale(
        onTap: _onTap,
        pressedScale: .985,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isFolder ? const Color(0x12FFFFFF) : Colors.transparent,
            border: Border.all(
              color: isFolder ? AppColors.sep : const Color(0x0AFFFFFF),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isFolder
                      ? AppColors.accent.withValues(alpha: .16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  isFolder
                      ? Icons.folder_rounded
                      : Icons.insert_drive_file_outlined,
                  color: isFolder ? AppColors.accent : AppColors.dim,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isFolder ? FontWeight.w600 : FontWeight.w400,
                    color: isFolder ? AppColors.txt : AppColors.dim,
                  ),
                ),
              ),
              // File count only when the folder actually has files.
              if (isFolder && widget.fileCount > 0) ...[
                Text(
                  '${widget.fileCount}',
                  style: const TextStyle(color: AppColors.dim, fontSize: 12),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                isFolder
                    ? Icons.chevron_right_rounded
                    : Icons.open_in_new_rounded,
                color: AppColors.dim,
                size: isFolder ? 18 : 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyFolders extends StatelessWidget {
  const _EmptyFolders({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.dim, fontSize: 13),
    ),
  );
}
