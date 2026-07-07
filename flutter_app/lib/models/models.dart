import 'dart:convert';

/// Project lifecycle status. String values match the Electron app's
/// `.edithub.json` manifests so existing projects load unchanged.
enum ProjectStatus {
  active,
  downloading,
  uploading,
  incloud,
  archive,
  ready;

  static ProjectStatus fromString(String? s) {
    switch (s) {
      case 'active':
        return ProjectStatus.active;
      case 'downloading':
        return ProjectStatus.downloading;
      case 'uploading':
        return ProjectStatus.uploading;
      case 'incloud':
        return ProjectStatus.incloud;
      case 'archive':
        return ProjectStatus.archive;
      default:
        return ProjectStatus.ready;
    }
  }

  String get value => name;
}

class ProjectInfo {
  final String id;
  final String name;
  final String? year;
  final String? month;
  final String createdAt;
  final String lastOpenedAt;
  final List<String> footageUrls;
  final ProjectStatus status;
  final Map<String, double> downloadProgress;

  /// Editor the project targets: 'davinci' or 'premiere'. Drives which NLE the
  /// Open button launches.
  final String editor;
  String? folderPath;
  int? sizeBytes;

  ProjectInfo({
    required this.id,
    required this.name,
    this.year,
    this.month,
    required this.createdAt,
    required this.lastOpenedAt,
    this.footageUrls = const [],
    this.status = ProjectStatus.ready,
    this.downloadProgress = const {},
    this.editor = 'davinci',
    this.folderPath,
    this.sizeBytes,
  });

  factory ProjectInfo.fromJson(Map<String, dynamic> j) {
    return ProjectInfo(
      id: (j['id'] ?? '') as String,
      name: (j['name'] ?? '') as String,
      year: j['year'] as String?,
      month: j['month'] as String?,
      createdAt: (j['createdAt'] ?? '') as String,
      lastOpenedAt: (j['lastOpenedAt'] ?? j['createdAt'] ?? '') as String,
      footageUrls:
          (j['footageUrls'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      status: ProjectStatus.fromString(j['status'] as String?),
      downloadProgress:
          (j['downloadProgress'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
          ) ??
          const {},
      editor: (j['editor'] as String?) ?? 'davinci',
      folderPath: j['folderPath'] as String?,
      sizeBytes: (j['sizeBytes'] as num?)?.toInt(),
    );
  }

  /// Serialized into `.edithub.json`. `folderPath` is intentionally omitted —
  /// it is derived from where the file lives, not stored.
  Map<String, dynamic> toManifestJson() => {
    'id': id,
    'name': name,
    if (year != null) 'year': year,
    if (month != null) 'month': month,
    'createdAt': createdAt,
    'lastOpenedAt': lastOpenedAt,
    'footageUrls': footageUrls,
    'status': status.value,
    'downloadProgress': downloadProgress,
    'editor': editor,
  };

  String toManifestString() =>
      const JsonEncoder.withIndent('  ').convert(toManifestJson());

  ProjectInfo copyWith({
    String? name,
    String? year,
    String? month,
    String? lastOpenedAt,
    List<String>? footageUrls,
    ProjectStatus? status,
    Map<String, double>? downloadProgress,
    String? editor,
    String? folderPath,
    int? sizeBytes,
  }) {
    return ProjectInfo(
      id: id,
      name: name ?? this.name,
      year: year ?? this.year,
      month: month ?? this.month,
      createdAt: createdAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      footageUrls: footageUrls ?? this.footageUrls,
      status: status ?? this.status,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      editor: editor ?? this.editor,
      folderPath: folderPath ?? this.folderPath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
    );
  }
}

class FolderEntry {
  final String name;
  final String path;
  final bool isFolder;
  final int? sizeBytes;
  final List<FolderEntry> children;

  FolderEntry({
    required this.name,
    required this.path,
    required this.isFolder,
    this.sizeBytes,
    this.children = const [],
  });
}

class AppSettings {
  final String projectsFolder;
  final String downloadsFolder;
  final String dropfxLibrary;
  final String davinciPath;
  final String premierePath;
  final int autoArchiveDays;
  final List<String> autoImportPatterns;
  final String icloudPath;

  const AppSettings({
    required this.projectsFolder,
    required this.downloadsFolder,
    required this.dropfxLibrary,
    required this.davinciPath,
    required this.premierePath,
    required this.autoArchiveDays,
    required this.autoImportPatterns,
    required this.icloudPath,
  });

  factory AppSettings.fromJson(Map<String, dynamic> j, AppSettings defaults) {
    return AppSettings(
      projectsFolder:
          (j['projectsFolder'] ?? defaults.projectsFolder) as String,
      downloadsFolder:
          (j['downloadsFolder'] ?? defaults.downloadsFolder) as String,
      dropfxLibrary: (j['dropfxLibrary'] ?? defaults.dropfxLibrary) as String,
      davinciPath: (j['davinciPath'] ?? defaults.davinciPath) as String,
      premierePath: (j['premierePath'] ?? defaults.premierePath) as String,
      autoArchiveDays:
          (j['autoArchiveDays'] as num?)?.toInt() ?? defaults.autoArchiveDays,
      autoImportPatterns:
          (j['autoImportPatterns'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          defaults.autoImportPatterns,
      icloudPath: (j['icloudPath'] ?? defaults.icloudPath) as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'projectsFolder': projectsFolder,
    'downloadsFolder': downloadsFolder,
    'dropfxLibrary': dropfxLibrary,
    'davinciPath': davinciPath,
    'premierePath': premierePath,
    'autoArchiveDays': autoArchiveDays,
    'autoImportPatterns': autoImportPatterns,
    'icloudPath': icloudPath,
  };

  AppSettings copyWith({
    String? projectsFolder,
    String? downloadsFolder,
    String? dropfxLibrary,
    String? davinciPath,
    String? premierePath,
    int? autoArchiveDays,
    List<String>? autoImportPatterns,
    String? icloudPath,
  }) {
    return AppSettings(
      projectsFolder: projectsFolder ?? this.projectsFolder,
      downloadsFolder: downloadsFolder ?? this.downloadsFolder,
      dropfxLibrary: dropfxLibrary ?? this.dropfxLibrary,
      davinciPath: davinciPath ?? this.davinciPath,
      premierePath: premierePath ?? this.premierePath,
      autoArchiveDays: autoArchiveDays ?? this.autoArchiveDays,
      autoImportPatterns: autoImportPatterns ?? this.autoImportPatterns,
      icloudPath: icloudPath ?? this.icloudPath,
    );
  }
}
