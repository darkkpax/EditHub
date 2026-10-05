import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/models.dart';
import 'project_store.dart';

/// Moves projects to the iCloud archive root and back. Mirrors `archiver.ts`,
/// with a copy+delete fallback when a plain rename would cross volumes.
class ArchiverService {
  final ProjectStore store;
  ArchiverService(this.store);

  /// Archive ("Сгрузить") a single project folder into
  /// `{archiveFolder}/{year}/{month}/{name}`. When [sourceRoot] is given, empty
  /// year/month folders left behind under it are removed from the local disk.
  Future<void> archiveProject(
    String projectFolder,
    String archiveFolder, {
    String? sourceRoot,
  }) async {
    final info = store.readProjectInfo(projectFolder);
    final folderName = p.basename(projectFolder);

    final destRoot = (info?.year != null && info?.month != null)
        ? p.join(archiveFolder, info!.year!, archiveMonthFolder(info.month))
        : archiveFolder;
    Directory(destRoot).createSync(recursive: true);

    var dest = p.join(destRoot, folderName);
    if (Directory(dest).existsSync()) {
      dest = p.join(
        destRoot,
        '${folderName}_${DateTime.now().millisecondsSinceEpoch}',
      );
    }

    final parent = p.dirname(projectFolder);
    _moveDirectory(projectFolder, dest);
    _setCloudPinState(dest, onlineOnly: true);
    _removeEmptyAncestors(parent, stopAt: sourceRoot);
  }

  /// Deletes now-empty parent folders (e.g. `{root}/2026/JULY`) left after a
  /// project moves out, stopping at the first non-empty dir or at [stopAt].
  void _removeEmptyAncestors(String dir, {String? stopAt}) {
    if (stopAt == null || !p.isWithin(p.normalize(stopAt), p.normalize(dir))) {
      return;
    }
    final floor = p.normalize(stopAt);
    var current = Directory(dir);
    while (current.existsSync()) {
      if (p.equals(p.normalize(current.path), floor)) break;
      try {
        if (current.listSync(followLinks: false).isNotEmpty) break;
        final parent = current.parent;
        current.deleteSync();
        current = parent;
      } catch (_) {
        break;
      }
    }
  }

  /// Moves an archived project back to the local projects folder. Returns the
  /// new local path so callers can re-read the manifest / re-fetch footage.
  Future<String> restoreFromArchive(
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
    _copyDirectory(Directory(archivePath), Directory(dest));
    final info = store.readProjectInfo(dest);
    if (info != null) {
      store.writeProjectInfo(
        dest,
        info.copyWith(
          status: info.status == ProjectStatus.paused
              ? ProjectStatus.paused
              : ProjectStatus.ready,
        ),
      );
    }
    _setCloudPinState(dest, onlineOnly: false);
    return dest;
  }

  /// Rename when possible (same volume), otherwise copy then delete the source.
  void _moveDirectory(String from, String to) {
    if (p.equals(p.absolute(from), p.absolute(to)) ||
        p.isWithin(p.absolute(from), p.absolute(to))) {
      throw FileSystemException(
        'Archive must be outside the project folder.',
        to,
      );
    }
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
      } else {
        throw FileSystemException(
          'Cannot safely copy a linked project entry.',
          entity.path,
        );
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
