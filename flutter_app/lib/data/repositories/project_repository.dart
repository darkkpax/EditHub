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
  // Project ids whose download was paused (not cancelled) — used to leave the
  // progress in place and mark the project `paused` rather than `ready`.
  final Set<String> _paused = {};

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

  bool isDownloading(String projectId) => _downloads.containsKey(projectId);

  /// Abandon the download. Completed files stay; the project returns to `ready`.
  void cancelDownload(String projectId) {
    _paused.remove(projectId);
    downloader.cancel(projectId);
  }

  /// Stop the download but keep the partial (`.part`) files and progress so it
  /// can be resumed later. Marks the project `paused`.
  void pauseDownload(String projectId) {
    _paused.add(projectId);
    downloader.cancel(projectId);
  }

  /// Resume a paused/interrupted download. The downloader picks up each file
  /// from its `.part` via an HTTP Range request, so no bytes are re-fetched.
  void resumeDownload(
    ProjectInfo project,
    void Function(ProjectInfo project)? onChanged,
  ) {
    if (_downloads.containsKey(project.id) || project.folderPath == null) return;
    _paused.remove(project.id);
    final folder = project.folderPath!;
    final running = (store.readProjectInfo(folder) ?? project).copyWith(
      folderPath: folder,
      status: ProjectStatus.downloading,
    );
    store.writeProjectInfo(folder, running);
    onChanged?.call(running);
    final task = _runDownloads(running, onChanged);
    _downloads[project.id] = task;
    unawaited(task.whenComplete(() => _downloads.remove(project.id)));
  }

  /// Adds footage link(s) to an existing project and downloads just the new
  /// ones. Throws synchronously (FormatException) on an invalid URL.
  void addFootage(
    ProjectInfo project,
    List<String> urls,
    void Function(ProjectInfo project)? onChanged,
  ) {
    final folder = project.folderPath;
    if (folder == null) return;
    final clean = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();
    for (final url in clean) {
      normalizeDownloadUrl(url); // validate before touching disk
    }
    final current = store.readProjectInfo(folder) ?? project;
    final newUrls = clean
        .where((url) => !current.footageUrls.contains(url))
        .toList();
    if (newUrls.isEmpty) return;
    final merged = [...current.footageUrls, ...newUrls];
    final updated = current.copyWith(
      folderPath: folder,
      footageUrls: merged,
      status: ProjectStatus.downloading,
    );
    store.writeProjectInfo(folder, updated);
    onChanged?.call(updated);
    if (_downloads.containsKey(project.id)) return;
    final task = _runDownloads(updated, onChanged, urls: newUrls);
    _downloads[project.id] = task;
    unawaited(task.whenComplete(() => _downloads.remove(project.id)));
  }

  Future<void> _runDownloads(
    ProjectInfo initial,
    void Function(ProjectInfo project)? onChanged, {
    List<String>? urls,
  }) async {
    final folder = initial.folderPath!;
    var paused = false;
    try {
      await downloader.downloadAll(
        projectId: initial.id,
        urls: urls ?? initial.footageUrls,
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
      // Distinguish a pause (keep progress, resumable) from a plain cancel.
      paused = _paused.remove(initial.id);
    } finally {
      final current = store.readProjectInfo(folder) ?? initial;
      final next = paused
          ? current.copyWith(folderPath: folder, status: ProjectStatus.paused)
          : current.copyWith(
              folderPath: folder,
              status: ProjectStatus.ready,
              downloadProgress: const {},
            );
      store.writeProjectInfo(folder, next);
      onChanged?.call(next);
    }
  }
}
