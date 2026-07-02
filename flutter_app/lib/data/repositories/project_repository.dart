import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/auth_session.dart';
import '../../models/models.dart';
import '../../services/downloader_service.dart';
import '../../services/project_store.dart';
import '../services/project_api_service.dart';

class ProjectRepository {
  ProjectRepository({required this.store, required this.downloader, this.api});

  final ProjectStore store;
  final DownloaderService downloader;
  final ProjectApiService? api;
  final Map<String, Future<void>> _downloads = {};

  Future<ProjectInfo> create({
    required String projectsFolder,
    required String name,
    required List<String> urls,
    String editor = 'davinci',
    AuthSession? session,
    void Function(ProjectInfo project)? onChanged,
    bool startDownloads = true,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty ||
        cleanName == '.' ||
        cleanName == '..' ||
        RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(cleanName)) {
      throw ArgumentError.value(name, 'name', 'Недопустимое имя проекта.');
    }
    final cleanUrls = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList();
    for (final url in cleanUrls) {
      normalizeDownloadUrl(url);
    }

    await Directory(projectsFolder).create(recursive: true);
    final folder = store.createProjectFolderStructure(
      projectsFolder,
      cleanName,
    );
    var project = store
        .createProjectInfo(cleanName, cleanUrls)
        .copyWith(
          folderPath: folder,
          editor: editor,
          status: cleanUrls.isEmpty
              ? ProjectStatus.ready
              : ProjectStatus.downloading,
        );
    store.writeProjectInfo(folder, project);

    try {
      if (session != null && api != null) {
        await api!.createProject(session, project);
      }
    } catch (_) {
      // The local project remains usable; the next catalog sync can upload it.
    }

    onChanged?.call(project);
    if (cleanUrls.isNotEmpty && startDownloads) {
      final task = _runDownloads(project, onChanged);
      _downloads[project.id] = task;
      unawaited(task.whenComplete(() => _downloads.remove(project.id)));
    }
    return project;
  }

  Future<void> waitForDownload(String projectId) =>
      _downloads[projectId] ?? Future<void>.value();

  void cancelDownload(String projectId) => downloader.cancel(projectId);

  Future<void> _runDownloads(
    ProjectInfo initial,
    void Function(ProjectInfo project)? onChanged,
  ) async {
    final folder = initial.folderPath!;
    try {
      await downloader.downloadAll(
        projectId: initial.id,
        urls: initial.footageUrls,
        destinationFolder: p.join(folder, 'FOOTAGE'),
        onProgress: (progress) {
          final current = store.readProjectInfo(folder) ?? initial;
          final updated = current.copyWith(
            folderPath: folder,
            status: ProjectStatus.downloading,
            downloadProgress: {
              ...current.downloadProgress,
              progress.fileUrl: progress.percent.toDouble(),
            },
          );
          store.writeProjectInfo(folder, updated);
          onChanged?.call(updated);
        },
      );
    } on DownloadCancelledException {
      // Cancellation leaves already completed files in place.
    } finally {
      final current = store.readProjectInfo(folder) ?? initial;
      final ready = current.copyWith(
        folderPath: folder,
        status: ProjectStatus.ready,
        downloadProgress: const {},
      );
      store.writeProjectInfo(folder, ready);
      onChanged?.call(ready);
    }
  }
}
