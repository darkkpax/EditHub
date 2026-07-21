import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme.dart';
import '../design/motion.dart';

/// Search field for the shared header strip. Transparent — the glass lives at
/// the screen level so the whole top reads as one continuous surface.
class ProjectSearchField extends StatelessWidget {
  const ProjectSearchField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('sidebar-header'),
    height: 116,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 58, 14, 10),
      child: TextField(
        onChanged: onChanged,
        decoration: const InputDecoration(
          hintText: 'Search projects',
          prefixIcon: Icon(Icons.search_rounded, size: 19),
          isDense: true,
        ),
      ),
    ),
  );
}

/// Sidebar body: the grouped, filtered project list. Header (search) lives in
/// the shared glass strip at the screen level.
class ProjectSidebar extends StatelessWidget {
  const ProjectSidebar({
    super.key,
    required this.projects,
    required this.selectedId,
    required this.onSelected,
    this.onContextMenu,
    this.query = '',
  });

  final List<ProjectInfo> projects;
  final String? selectedId;
  final ValueChanged<ProjectInfo> onSelected;
  final void Function(ProjectInfo project, Offset globalPosition)? onContextMenu;
  final String query;

  @override
  Widget build(BuildContext context) {
    final filtered = projects
        .where(
          (project) =>
              project.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    final groups = <String, List<ProjectInfo>>{};
    for (final project in filtered) {
      groups.putIfAbsent(_period(project), () => []).add(project);
    }
    var rowIndex = 0;

    return SizedBox(
      key: const Key('projects-sidebar'),
      width: 320,
      child: Stack(
        children: [
          const Positioned(
            top: 116,
            left: 0,
            right: 0,
            bottom: 0,
            child: ColoredBox(color: AppColors.fill1),
          ),
          Positioned.fill(
            child: groups.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(22, 136, 22, 22),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        'No projects found.',
                        style: TextStyle(color: AppColors.dim, fontSize: 13),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(10, 124, 10, 88),
                    children: [
                      for (final group in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                          child: Text(
                            group.key.toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.dim,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .7,
                            ),
                          ),
                        ),
                        for (final project in group.value)
                          FadeInUp(
                            delay: Duration(
                              milliseconds: (rowIndex++ * 24).clamp(0, 240),
                            ),
                            child: _ProjectRow(
                              project: project,
                              selected: selectedId == project.id,
                              onTap: () => onSelected(project),
                              onContextMenu: onContextMenu == null
                                  ? null
                                  : (pos) => onContextMenu!(project, pos),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
          const Positioned(
            key: Key('sidebar-divider'),
            top: 116,
            right: 0,
            bottom: 0,
            width: 1,
            child: ColoredBox(color: Colors.transparent),
          ),
        ],
      ),
    );
  }

  String _period(ProjectInfo project) {
    final month = project.month;
    if (month == null || project.year == null) return 'Projects';
    return '${month[0]}${month.substring(1).toLowerCase()} ${project.year}';
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.project,
    required this.selected,
    required this.onTap,
    this.onContextMenu,
  });

  final ProjectInfo project;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: GestureDetector(
      onSecondaryTapDown: onContextMenu == null
          ? null
          : (details) => onContextMenu!(details.globalPosition),
      child: PressableScale(
        onTap: onTap,
        pressedScale: .98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: .2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppColors.radiusXs),
          border: Border.all(
            color: selected
                ? AppColors.accent.withValues(alpha: .12)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color:
                    (project.status == ProjectStatus.archive
                            ? AppColors.warn
                            : AppColors.accent)
                        .withValues(alpha: selected ? .2 : .14),
                borderRadius: BorderRadius.circular(AppColors.radiusXs),
              ),
              child: Icon(
                project.status == ProjectStatus.archive
                    ? Icons.cloud_rounded
                    : Icons.folder_rounded,
                color: project.status == ProjectStatus.archive
                    ? AppColors.warn
                    : AppColors.accent,
                size: 21,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _status(project.status),
                    style: TextStyle(
                      color: project.status == ProjectStatus.downloading
                          ? AppColors.warn
                          : AppColors.dim,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    ),
  );

  String _status(ProjectStatus status) => switch (status) {
    ProjectStatus.downloading => 'Downloading',
    ProjectStatus.paused => 'Paused',
    ProjectStatus.uploading => 'Uploading to iCloud',
    ProjectStatus.archive || ProjectStatus.incloud => 'In iCloud',
    ProjectStatus.active => 'Open',
    ProjectStatus.ready => 'Ready',
  };
}
