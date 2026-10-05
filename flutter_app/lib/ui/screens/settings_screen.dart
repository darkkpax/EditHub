import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../../services/updater_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 68, 20, 20),
      children: [
        Text(
          'Settings',
          style: TextStyle(
            color: AppColors.of(context).txt,
            fontFamily: 'Newsreader',
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 20),
        Text(
          'Appearance',
          style: TextStyle(
            fontFamily: 'Newsreader',
            fontSize: 22,
            color: AppColors.of(context).txt,
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'dark',
              label: Text('Dark'),
              icon: Icon(Icons.dark_mode_outlined),
            ),
            ButtonSegment(
              value: 'light',
              label: Text('Light'),
              icon: Icon(Icons.light_mode_outlined),
            ),
            ButtonSegment(
              value: 'system',
              label: Text('System'),
              icon: Icon(Icons.brightness_auto_outlined),
            ),
          ],
          selected: {
            ['dark', 'light', 'system'].contains(settings.theme)
                ? settings.theme
                : 'dark',
          },
          onSelectionChanged: (values) =>
              notifier.update((s) => s.copyWith(theme: values.single)),
        ),
        const SizedBox(height: 24),
        Text(
          'Storage',
          style: TextStyle(
            fontFamily: 'Newsreader',
            fontSize: 22,
            color: AppColors.of(context).txt,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Projects stay here until you choose to archive or delete them.',
          style: TextStyle(color: AppColors.of(context).dim),
        ),
        const SizedBox(height: 12),
        _FolderRow(
          label: 'Projects folder',
          value: settings.projectsFolder,
          onPick: (dir) =>
              notifier.update((s) => s.copyWith(projectsFolder: dir)),
        ),
        _FolderRow(
          label: 'iCloud Drive',
          value: settings.icloudPath,
          onPick: (dir) => notifier.update((s) => s.copyWith(icloudPath: dir)),
        ),
        _FolderRow(
          label: 'Downloads folder',
          value: settings.downloadsFolder,
          onPick: (dir) =>
              notifier.update((s) => s.copyWith(downloadsFolder: dir)),
        ),
        _FolderRow(
          label: 'DropFX library (SFX)',
          value: settings.dropfxLibrary,
          onPick: (dir) =>
              notifier.update((s) => s.copyWith(dropfxLibrary: dir)),
        ),
        SizedBox(height: 12),
        _TextRow(
          label: 'DaVinci Resolve path',
          value: settings.davinciPath,
          onChanged: (v) => notifier.update((s) => s.copyWith(davinciPath: v)),
        ),
        SizedBox(height: 12),
        _TextRow(
          label: 'Adobe Premiere Pro path',
          value: settings.premierePath,
          onChanged: (v) => notifier.update((s) => s.copyWith(premierePath: v)),
        ),
        SizedBox(height: 12),
        const _GoogleDriveRow(),
        SizedBox(height: 12),
        const _ExportProjectsRow(),
        const SizedBox(height: 24),
        const _UpdateRow(),
      ],
    );
  }
}

class _UpdateRow extends StatefulWidget {
  const _UpdateRow();
  @override
  State<_UpdateRow> createState() => _UpdateRowState();
}

class _UpdateRowState extends State<_UpdateRow> {
  bool _busy = false;
  final _updater = UpdaterService();
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: OutlinedButton.icon(
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await _updater.check(context: context, interactive: true);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      icon: const Icon(Icons.system_update_alt_outlined, size: 18),
      label: Text(_busy ? 'Checking for updates…' : 'Check for updates'),
    ),
  );
}

/// One-shot: export a `.drp` into every current DaVinci project's folder.
class _ExportProjectsRow extends ConsumerStatefulWidget {
  const _ExportProjectsRow();

  @override
  ConsumerState<_ExportProjectsRow> createState() => _ExportProjectsRowState();
}

class _ExportProjectsRowState extends ConsumerState<_ExportProjectsRow> {
  bool _busy = false;

  Future<void> _exportAll() async {
    final folders = (ref.read(projectsProvider).value ?? [])
        .where(
          (project) =>
              project.editor == 'davinci' &&
              project.folderPath != null &&
              project.status != ProjectStatus.archive &&
              project.status != ProjectStatus.incloud,
        )
        .map((project) => project.folderPath!)
        .toList();
    if (folders.isEmpty) {
      _snack('No local DaVinci projects to export.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(davinciServiceProvider)
          .exportAll(ref.read(settingsProvider).davinciPath, folders);
      _snack(
        'Exported ${result.exported} of ${result.total} project file(s).'
        '${result.exported < result.total && result.message != null ? ' Last error: ${result.message}' : ''}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DaVinci project files',
          style: TextStyle(color: AppColors.of(context).dim, fontSize: 13),
        ),
        SizedBox(height: 6),
        FilledButton.icon(
          onPressed: _busy ? null : _exportAll,
          icon: _busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.save_alt_rounded),
          label: Text('Export .drp for all projects'),
        ),
        SizedBox(height: 4),
        Text(
          'Requires DaVinci Resolve open with scripting enabled. Switches the '
          'active project as it exports each one.',
          style: TextStyle(color: AppColors.of(context).dim, fontSize: 11),
        ),
      ],
    );
  }
}

/// Connect button that flips to a "connected" state once signed in.
class _GoogleDriveRow extends ConsumerStatefulWidget {
  const _GoogleDriveRow();

  @override
  ConsumerState<_GoogleDriveRow> createState() => _GoogleDriveRowState();
}

class _GoogleDriveRowState extends ConsumerState<_GoogleDriveRow> {
  late bool _connected = ref.read(googleDriveAuthProvider).isSignedIn;
  bool _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await ref.read(googleDriveAuthProvider).signIn();
      if (mounted) {
        setState(
          () => _connected = ref.read(googleDriveAuthProvider).isSignedIn,
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Google Drive connected')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_connected) {
      return Row(
        children: [
          Icon(Icons.check_circle, color: AppColors.of(context).good, size: 20),
          SizedBox(width: 8),
          Text(
            'Google Drive connected',
            style: TextStyle(color: AppColors.of(context).txt, fontSize: 13),
          ),
          Spacer(),
          TextButton(
            onPressed: _busy ? null : _connect,
            child: Text('Reconnect'),
          ),
        ],
      );
    }
    return FilledButton.icon(
      onPressed: _busy ? null : _connect,
      icon: Icon(Icons.add_to_drive),
      label: Text('Connect Google Drive'),
    );
  }
}

class _FolderRow extends StatelessWidget {
  final String label;
  final String value;
  final void Function(String dir) onPick;

  const _FolderRow({
    required this.label,
    required this.value,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: AppColors.of(context).dim, fontSize: 13),
          ),
          SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.of(context).fill2,
                    borderRadius: BorderRadius.circular(AppColors.radiusSm),
                    border: Border.all(color: AppColors.of(context).sep),
                  ),
                  child: Text(
                    value.isEmpty ? '—' : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.of(context).txt,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  final dir = await FilePicker.getDirectoryPath();
                  if (dir != null) onPick(dir);
                },
                child: Text('Choose'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TextRow extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _TextRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AppColors.of(context).dim, fontSize: 13),
        ),
        SizedBox(height: 6),
        TextFormField(
          initialValue: value,
          style: TextStyle(color: AppColors.of(context).txt, fontSize: 13),
          onFieldSubmitted: onChanged,
        ),
      ],
    );
  }
}
