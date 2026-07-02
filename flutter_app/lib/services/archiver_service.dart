import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/models.dart';
import 'project_store.dart';

/// Moves projects to the iCloud archive root and back. Mirrors `archiver.ts`,
/// with a copy+delete fallback when a plain rename would cross volumes.
class ArchiverService {
  final ProjectStore store;
  ArchiverService(this.store);

  static const _months = [
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];

  /// Archive ("Сгрузить") a single project folder into
  /// `{archiveFolder}/{year}/{month}/{name}`.
  Future<void> archiveProject(
    String projectFolder,
    String archiveFolder,
  ) async {
    final info = store.readProjectInfo(projectFolder);
    final folderName = p.basename(projectFolder);

    final destRoot = (info?.year != null && info?.month != null)
        ? p.join(archiveFolder, info!.year!, info.month!)
        : archiveFolder;
    Directory(destRoot).createSync(recursive: true);

    var dest = p.join(destRoot, folderName);
    if (Directory(dest).existsSync()) {
      dest = p.join(
        destRoot,
        '${folderName}_${DateTime.now().millisecondsSinceEpoch}',
      );
    }

    _moveDirectory(projectFolder, dest);
    _setCloudPinState(dest, onlineOnly: true);
  }

  Future<void> restoreFromArchive(
    String archivePath,
    String projectsFolder,
  ) async {
    final folderName = p.basename(archivePath);
    final parent = p.dirname(archivePath);
    final month = p.basename(parent);
    final year = p.basename(p.dirname(parent));
    final destRoot = RegExp(r'^\d{4}$').hasMatch(year)
        ? p.join(projectsFolder, year, month)
        : projectsFolder;
    Directory(destRoot).createSync(recursive: true);

    var dest = p.join(destRoot, folderName);
    if (Directory(dest).existsSync()) {
      dest = p.join(
        destRoot,
        '${folderName}_restored_${DateTime.now().millisecondsSinceEpoch}',
      );
    }
    _moveDirectory(archivePath, dest);
    _setCloudPinState(dest, onlineOnly: false);
  }

  /// Auto-archive: projects not from the current month, or untouched longer
  /// than [autoArchiveDays], get moved to the archive (skipping the active one).
  Future<void> runAutoArchive({
    required String projectsFolder,
    required String archiveFolder,
    required int autoArchiveDays,
  }) async {
    if (!Directory(projectsFolder).existsSync()) return;
    final now = DateTime.now();
    final currentYear = now.year.toString();
    final currentMonth = _months[now.month - 1];
    final thresholdMs = autoArchiveDays * 24 * 60 * 60 * 1000;

    for (final project in store.listProjects(projectsFolder)) {
      final folder = project.folderPath;
      if (folder == null || project.status == ProjectStatus.active) continue;

      final isCurrentMonth =
          project.year == currentYear &&
          project.month?.toUpperCase() == currentMonth;
      final lastOpened =
          DateTime.tryParse(
            project.lastOpenedAt.isNotEmpty
                ? project.lastOpenedAt
                : project.createdAt,
          )?.millisecondsSinceEpoch ??
          0;
      final age = now.millisecondsSinceEpoch - lastOpened;

      if (!isCurrentMonth || age >= thresholdMs) {
        try {
          await archiveProject(folder, archiveFolder);
        } catch (e) {
          // ignore: avoid_print
          print('Auto-archive failed for $folder: $e');
        }
      }
    }
  }

  /// Rename when possible (same volume), otherwise copy then delete the source.
  void _moveDirectory(String from, String to) {
    final src = Directory(from);
    try {
      src.renameSync(to);
      return;
    } on FileSystemException {
      // Cross-device or locked — fall back to recursive copy.
    }
    _copyDirectory(src, Directory(to));
    src.deleteSync(recursive: true);
  }

  void _copyDirectory(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final entity in from.listSync(followLinks: false)) {
      final newPath = p.join(to.path, p.basename(entity.path));
      if (entity is Directory) {
        _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        entity.copySync(newPath);
      }
    }
  }

  /// Best-effort "free up space" hint via the Windows Cloud Filter attributes
  /// (`attrib +U -P` = online-only). iCloud for Windows may or may not honor
  /// these, so callers should not assume local space is reclaimed immediately.
  void _setCloudPinState(String target, {required bool onlineOnly}) {
    if (!Platform.isWindows || !Directory(target).existsSync()) return;
    final args = onlineOnly
        ? ['+U', '-P', '/S', '/D', target]
        : ['-U', '+P', '/S', '/D', target];
    try {
      Process.runSync('attrib.exe', args);
    } catch (e) {
      // ignore: avoid_print
      print('Cloud pin state update failed for $target: $e');
    }
  }
}
