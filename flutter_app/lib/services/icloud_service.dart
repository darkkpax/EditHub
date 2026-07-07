import 'dart:io';

import 'package:path/path.dart' as p;

import 'project_store.dart';

/// Resolves the iCloud Drive location and exposes the single archive root
/// (`{icloud}/Videos`) plus sync-status helpers. Mirrors the Electron
/// `icloud.ts` after the folder unification fix.
class ICloudService {
  String icloudPath;

  ICloudService(String configuredPath) : icloudPath = _resolve(configuredPath);

  void updatePath(String configuredPath) {
    icloudPath = _resolve(configuredPath);
  }

  static String _resolve(String configured) {
    final fromRegistry = _fromRegistry();
    if (fromRegistry != null && Directory(fromRegistry).existsSync()) {
      return fromRegistry;
    }
    if (configured.isNotEmpty && Directory(configured).existsSync()) {
      return configured;
    }
    final home = Platform.environment['USERPROFILE'] ?? '';
    for (final c in [
      p.join(home, 'iCloudDrive'),
      p.join(home, 'Library', 'Mobile Documents', 'com~apple~CloudDocs'),
    ]) {
      if (Directory(c).existsSync()) return c;
    }
    return configured;
  }

  static String? _fromRegistry() {
    if (!Platform.isWindows) return null;
    try {
      final result = Process.runSync('reg', [
        'query',
        r'HKCU\Software\Apple Inc.\Internet Services',
        '/v',
        'ICDrive',
      ]);
      if (result.exitCode != 0) return null;
      final match = RegExp(
        r'ICDrive\s+REG_SZ\s+(.+)',
      ).firstMatch(result.stdout.toString());
      return match?.group(1)?.trim();
    } catch (_) {
      return null;
    }
  }

  /// Single source of truth for archived projects: `{icloud}/edithub/Videos`,
  /// then sorted `/{year}/{month}/{project}` by the archiver.
  String get archiveFolder => p.join(icloudPath, 'edithub', 'Videos');

  List<String> get archiveSearchFolders => {
    archiveFolder,
    p.join(icloudPath, 'Videos'),
    p.join(icloudPath, 'EditHub', 'Videos'),
    p.join(icloudPath, 'Edit Hub', 'Videos'),
  }.where((path) => Directory(path).existsSync()).toList();

  String prepareArchive() => prepareArchiveAt(icloudPath);

  /// Consolidates the legacy roots used by older builds and normalizes month
  /// folders without touching project contents.
  static String prepareArchiveAt(String cloudPath) {
    final canonical = p.join(cloudPath, 'edithub', 'Videos');
    Directory(canonical).createSync(recursive: true);
    final roots = {
      p.join(cloudPath, 'Videos'),
      p.join(cloudPath, 'EditHub', 'Videos'),
      p.join(cloudPath, 'Edit Hub', 'Videos'),
      canonical,
    };

    for (final rootPath in roots) {
      final root = Directory(rootPath);
      if (!root.existsSync()) continue;
      for (final year in _directories(root)) {
        final yearName = p.basename(year.path);
        if (!RegExp(r'^\d{4}$').hasMatch(yearName)) continue;
        for (final month in _directories(year)) {
          final mm = archiveMonthFolder(p.basename(month.path));
          if (mm.isEmpty) continue;
          for (final project in _directories(month)) {
            final destinationDir = Directory(p.join(canonical, yearName, mm));
            destinationDir.createSync(recursive: true);
            var destination = p.join(
              destinationDir.path,
              p.basename(project.path),
            );
            if (p.equals(project.path, destination)) continue;
            if (Directory(destination).existsSync()) {
              destination =
                  '${destination}_${DateTime.now().millisecondsSinceEpoch}';
            }
            try {
              project.renameSync(destination);
            } catch (_) {
              // iCloud can temporarily lock placeholders; the next scan tries
              // again and the legacy root remains visible until then.
            }
          }
          _deleteIfEmpty(month);
        }
        _deleteIfEmpty(year);
      }
      if (!p.equals(root.path, canonical)) _deleteIfEmpty(root);
    }
    return canonical;
  }

  static List<Directory> _directories(Directory directory) {
    try {
      return directory
          .listSync(followLinks: false)
          .whereType<Directory>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static void _deleteIfEmpty(Directory directory) {
    try {
      if (directory.existsSync() &&
          directory.listSync(followLinks: false).isEmpty) {
        directory.deleteSync();
      }
    } catch (_) {}
  }

  /// True while iCloud is up/downloading: a `.icloud` placeholder exists or a
  /// file under the archive root was touched in the last 60s.
  bool isSyncing() {
    final root = Directory(archiveFolder);
    if (!root.existsSync()) return false;
    final now = DateTime.now();
    bool check(Directory dir, int depth) {
      if (depth > 4) return false;
      try {
        for (final e in dir.listSync(followLinks: false)) {
          final name = p.basename(e.path);
          if (name.endsWith('.icloud')) return true;
          if (e is File) {
            try {
              if (now.difference(e.statSync().modified).inSeconds < 60) {
                return true;
              }
            } catch (_) {}
          } else if (e is Directory && check(e, depth + 1)) {
            return true;
          }
        }
      } catch (_) {}
      return false;
    }

    return check(root, 0);
  }

  /// Names of project folders (under Videos/{year}/{month}) touched recently —
  /// i.e. likely mid-upload.
  List<String> getUploadingProjects() {
    final uploading = <String>[];
    final root = Directory(archiveFolder);
    if (!root.existsSync()) return uploading;
    final now = DateTime.now();
    List<Directory> dirs(Directory d) {
      try {
        return d
            .listSync(followLinks: false)
            .whereType<Directory>()
            .where(
              (e) =>
                  !p.basename(e.path).toLowerCase().startsWith('__extracting_'),
            )
            .toList();
      } catch (_) {
        return [];
      }
    }

    for (final year in dirs(root)) {
      for (final month in dirs(year)) {
        for (final project in dirs(month)) {
          try {
            if (now.difference(project.statSync().modified).inMinutes < 5) {
              uploading.add(p.basename(project.path));
            }
          } catch (_) {}
        }
      }
    }
    return uploading;
  }
}
