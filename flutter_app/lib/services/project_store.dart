import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/models.dart';

const String kProjectManifest = '.edithub.json';
const String kProjectMetadata = '.edithub-metadata.json';

const _archiveMonths = {
  '01': 'JANUARY',
  '02': 'FEBRUARY',
  '03': 'MARCH',
  '04': 'APRIL',
  '05': 'MAY',
  '06': 'JUNE',
  '07': 'JULY',
  '08': 'AUGUST',
  '09': 'SEPTEMBER',
  '10': 'OCTOBER',
  '11': 'NOVEMBER',
  '12': 'DECEMBER',
};

String archiveMonthFolder(String? month) {
  final value = month?.toUpperCase() ?? '';
  return _archiveMonths[value] ?? value;
}

bool _isArchiveMonth(String value) {
  final upper = value.toUpperCase();
  return _archiveMonths.containsKey(upper) ||
      _archiveMonths.containsValue(upper);
}

/// Subfolders created for every new project (matches the Electron app).
const List<String> kDefaultProjectFolders = [
  'FOOTAGE',
  'SFX',
  'MUSIC',
  'READY VIDEOS',
  'MISC',
  'VOICE/ENCHANCE',
  'VOICE/NOT ENCHANCE',
  'DOCS',
  'GRAPHICS',
  'B-ROLL',
  'SUBS',
];

const Set<String> kVideoExtensions = {
  '.mp4',
  '.mov',
  '.m4v',
  '.avi',
  '.mkv',
  '.webm',
  '.braw',
};

class ProjectStore {
  static const _uuid = Uuid();

  /// Stable id derived from the folder path — identical to the Electron app's
  /// `sha1(path.toLowerCase())[:32]` so manifests/ids line up.
  static String stableIdFromPath(String folder) {
    return sha1
        .convert(utf8.encode(folder.toLowerCase()))
        .toString()
        .substring(0, 32);
  }

  static Map<String, dynamic>? _readJson(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Reads a Windows `.edithub.json` manifest, deriving year/month from the
  /// `{year}/{month}/{project}` path when the manifest omits them.
  ProjectInfo? readProjectInfo(String projectFolder) {
    final json = _readJson(p.join(projectFolder, kProjectManifest));
    if (json == null) return null;
    final info = ProjectInfo.fromJson(json)..folderPath = projectFolder;
    if (info.year == null || info.month == null) {
      final parts = p.split(projectFolder);
      final month =
          info.month ?? (parts.length >= 2 ? parts[parts.length - 2] : null);
      final year =
          info.year ?? (parts.length >= 3 ? parts[parts.length - 3] : null);
      return info.copyWith(year: year, month: month);
    }
    return info;
  }

  /// Reads a project archived by the Mac app (`{name}.edithub` /
  /// `.edithub-metadata.json`) or a footage-only folder.
  ProjectInfo? _readMacProjectInfo(
    String projectFolder,
    String? year,
    String? month,
  ) {
    try {
      final dir = Directory(projectFolder);
      if (!dir.existsSync()) return null;
      final name = p.basename(projectFolder);
      final metadata = _readJson(p.join(projectFolder, kProjectMetadata));
      final macManifest = _readJson(p.join(projectFolder, '$name.edithub'));
      final stat = dir.statSync();
      final footage =
          (metadata?['footageLinks'] ?? macManifest?['footageLinks'])
              as List? ??
          const [];
      return ProjectInfo(
        id:
            (metadata?['projectId'] ??
                    macManifest?['projectId'] ??
                    stableIdFromPath(projectFolder))
                as String,
        name: name,
        year: year,
        month: month,
        createdAt: stat.changed.toUtc().toIso8601String(),
        lastOpenedAt: stat.modified.toUtc().toIso8601String(),
        footageUrls: footage.map((e) => e.toString()).toList(),
        status: macManifest != null
            ? ProjectStatus.archive
            : ProjectStatus.ready,
        folderPath: projectFolder,
      );
    } catch (_) {
      return null;
    }
  }

  void writeProjectInfo(String projectFolder, ProjectInfo info) {
    File(
      p.join(projectFolder, kProjectManifest),
    ).writeAsStringSync(info.toManifestString());
  }

  ProjectInfo createProjectInfo(String name, List<String> urls) {
    final now = DateTime.now().toUtc().toIso8601String();
    return ProjectInfo(
      id: _uuid.v4(),
      name: name,
      year: DateTime.now().year.toString(),
      month: _monthName(DateTime.now().month),
      createdAt: now,
      lastOpenedAt: now,
      footageUrls: urls,
      status: urls.isEmpty ? ProjectStatus.ready : ProjectStatus.downloading,
    );
  }

  /// Scans `projectsFolder` (and nested year/month folders) for projects.
  List<ProjectInfo> listProjects(String projectsFolder) {
    final results = <ProjectInfo>[];
    final seen = <String>{};

    void push(ProjectInfo? info) {
      if (info == null || seen.contains(info.id)) return;
      seen.add(info.id);
      // Size is computed lazily per selected project in the detail view — never
      // walk every project's tree during a scan (that's a full-disk crawl).
      results.add(info);
    }

    void scanProjectDir(String path, String? year, String? month) {
      final win = readProjectInfo(path);
      if (win != null) {
        win.folderPath = path;
        push(win);
        return;
      }
      push(_readMacProjectInfo(path, year, month));
    }

    void scanFolder(String folder, int depth, String? year, String? month) {
      if (depth > 3) return;
      final dir = Directory(folder);
      if (!dir.existsSync()) return;
      for (final entry in dir.listSync(followLinks: false)) {
        if (entry is! Directory) continue;
        final name = p.basename(entry.path);
        if (name.startsWith('.') ||
            name == 'node_modules' ||
            name.toLowerCase().startsWith('__extracting_')) {
          continue;
        }
        final isYear = RegExp(r'^\d{4}$').hasMatch(name);
        final nextYear = isYear ? name : year;
        final nextMonth = year != null && _isArchiveMonth(name)
            ? archiveMonthFolder(name)
            : month;

        final hasWin = File(p.join(entry.path, kProjectManifest)).existsSync();
        final hasMac = File(p.join(entry.path, '$name.edithub')).existsSync();
        final hasMeta = File(p.join(entry.path, kProjectMetadata)).existsSync();
        if (hasWin || hasMac || hasMeta || (year != null && month != null)) {
          scanProjectDir(entry.path, year, month);
          continue;
        }
        scanFolder(entry.path, depth + 1, nextYear, nextMonth);
      }
    }

    scanFolder(projectsFolder, 0, null, null);
    results.sort((a, b) => _sortTime(b).compareTo(_sortTime(a)));
    return results;
  }

  /// Archived projects live as folders under `{icloud}/Videos/{year}/{month}`,
  /// so listing them is the same folder scan as active projects.
  List<ProjectInfo> listArchivedProjects(String archiveFolder) {
    return listProjects(
      archiveFolder,
    ).map((p) => p.copyWith(status: ProjectStatus.archive)).toList();
  }

  int getFolderSizeBytes(String folderPath) {
    var total = 0;
    try {
      final dir = Directory(folderPath);
      if (!dir.existsSync()) return 0;
      for (final entry in dir.listSync(recursive: true, followLinks: false)) {
        if (entry is File) {
          try {
            total += entry.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// Removes orphaned `__extracting_*` temp folders from interrupted zip
  /// extractions: a temp dir is dropped if a real sibling with the cleaned
  /// name exists, or if it is older than [staleAfter].
  ({int removed, int bytesFreed}) sweepExtractingDirs(
    List<String> folders, {
    Duration staleAfter = const Duration(hours: 1),
  }) {
    var removed = 0;
    var bytesFreed = 0;
    final now = DateTime.now();
    final seenRoots = <String>{};

    String cleanName(String name) => name
        .replaceFirst(RegExp(r'^__extracting_', caseSensitive: false), '')
        .replaceFirst(RegExp(r'_\d{10,}.*$'), '');

    void walk(String dir, int depth) {
      if (depth > 4) return;
      final d = Directory(dir);
      if (!d.existsSync()) return;
      List<FileSystemEntity> entries;
      try {
        entries = d.listSync(followLinks: false);
      } catch (_) {
        return;
      }
      for (final entry in entries) {
        if (entry is! Directory) continue;
        final name = p.basename(entry.path);
        if (name.toLowerCase().startsWith('__extracting_')) {
          final twin = p.join(dir, cleanName(name));
          var stale = false;
          try {
            stale = now.difference(entry.statSync().modified) > staleAfter;
          } catch (_) {}
          final hasTwin = twin != entry.path && Directory(twin).existsSync();
          if (hasTwin || stale) {
            try {
              final size = getFolderSizeBytes(entry.path);
              entry.deleteSync(recursive: true);
              removed++;
              bytesFreed += size;
            } catch (_) {}
          }
          continue;
        }
        walk(entry.path, depth + 1);
      }
    }

    for (final folder in folders) {
      final resolved = p.normalize(folder);
      if (seenRoots.contains(resolved)) continue;
      seenRoots.add(resolved);
      walk(resolved, 0);
    }
    return (removed: removed, bytesFreed: bytesFreed);
  }

  String createProjectFolderStructure(String parentFolder, String projectName) {
    final now = DateTime.now();
    final folder = p.join(
      parentFolder,
      now.year.toString(),
      _monthName(now.month),
      projectName,
    );
    if (Directory(folder).existsSync()) {
      throw FileSystemException(
        'A project with that name already exists.',
        folder,
      );
    }
    Directory(folder).createSync(recursive: true);
    for (final sub in kDefaultProjectFolders) {
      Directory(
        p.join(folder, sub.replaceAll('/', Platform.pathSeparator)),
      ).createSync(recursive: true);
    }
    return folder;
  }

  List<FolderEntry> listProjectFolders(String projectFolder) {
    List<FolderEntry> read(String dir, int depth) {
      final d = Directory(dir);
      if (!d.existsSync() || depth > 3) return [];
      final entries =
          d
              .listSync(followLinks: false)
              .where((e) => !p.basename(e.path).startsWith('.'))
              .toList()
            ..sort((a, b) {
              final ad = a is Directory ? 0 : 1;
              final bd = b is Directory ? 0 : 1;
              if (ad != bd) return ad - bd;
              return p.basename(a.path).compareTo(p.basename(b.path));
            });
      return entries.map((e) {
        final name = p.basename(e.path);
        if (e is Directory) {
          return FolderEntry(
            name: name,
            path: e.path,
            isFolder: true,
            children: read(e.path, depth + 1),
          );
        }
        int? size;
        try {
          size = (e as File).lengthSync();
        } catch (_) {}
        return FolderEntry(
          name: name,
          path: e.path,
          isFolder: false,
          sizeBytes: size,
        );
      }).toList();
    }

    return read(projectFolder, 0);
  }

  String? findProjectPreviewVideo(String projectFolder) {
    for (final folder in [
      'FOOTAGE',
      'Footage',
      'READY VIDEOS',
      'READY VIDEO',
      'Ready Videos',
    ]) {
      final found = _findFirstVideo(p.join(projectFolder, folder));
      if (found != null) return found;
    }
    return _findFirstVideo(projectFolder);
  }

  String? _findFirstVideo(String root) {
    final dir = Directory(root);
    if (!dir.existsSync()) return null;
    try {
      final entries = dir.listSync(followLinks: false);
      for (final e in entries) {
        if (e is File &&
            kVideoExtensions.contains(p.extension(e.path).toLowerCase())) {
          return e.path;
        }
      }
      for (final e in entries) {
        if (e is Directory) {
          final found = _findFirstVideo(e.path);
          if (found != null) return found;
        }
      }
    } catch (_) {}
    return null;
  }

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

  static String _monthName(int month) => _months[month - 1];

  int _sortTime(ProjectInfo project) {
    final year = int.tryParse(project.year ?? '');
    final monthIdx = project.month != null
        ? _months.indexOf(project.month!.toUpperCase())
        : -1;
    final updated = DateTime.tryParse(
      project.lastOpenedAt.isNotEmpty
          ? project.lastOpenedAt
          : project.createdAt,
    )?.millisecondsSinceEpoch;
    if (year != null && monthIdx >= 0) {
      final base = DateTime.utc(year, monthIdx + 1, 1).millisecondsSinceEpoch;
      const monthMs = 31 * 24 * 60 * 60 * 1000;
      return base + (updated != null ? updated % monthMs : 0);
    }
    return updated ?? 0;
  }
}
