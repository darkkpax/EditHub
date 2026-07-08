import 'dart:async';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/repositories/project_repository.dart';
import '../data/services/auth_storage_service.dart';
import '../data/services/project_api_service.dart';
import '../domain/models/auth_session.dart';
import '../models/models.dart';
import '../services/archiver_service.dart';
import '../services/davinci_service.dart';
import '../services/downloader_service.dart';
import '../services/editor_service.dart';
import '../services/icloud_service.dart';
import '../services/google_drive_auth_service.dart';
import '../services/project_store.dart';
import '../services/settings_service.dart';
import '../services/shell_service.dart';

enum AppTab { projects, settings }

final settingsServiceProvider = Provider((_) => SettingsService());
final projectStoreProvider = Provider((_) => ProjectStore());
final shellServiceProvider = Provider((_) => const ShellService());
final downloaderServiceProvider = Provider(
  (ref) =>
      DownloaderService(googleDriveAuth: ref.read(googleDriveAuthProvider)),
);
final projectApiServiceProvider = Provider((_) => ProjectApiService());
final projectRepositoryProvider = Provider(
  (ref) => ProjectRepository(
    store: ref.read(projectStoreProvider),
    downloader: ref.read(downloaderServiceProvider),
    api: ref.read(projectApiServiceProvider),
  ),
);
final davinciServiceProvider = Provider((_) => DaVinciService());
final editorServiceProvider = Provider((_) => EditorService());
final googleDriveAuthProvider = Provider((_) => GoogleDriveAuthService());
final archiverServiceProvider = Provider(
  (ref) => ArchiverService(ref.read(projectStoreProvider)),
);
final icloudServiceProvider = Provider(
  (ref) => ICloudService(ref.watch(settingsProvider).icloudPath),
);
final authStorageServiceProvider = Provider(
  (ref) =>
      AuthStorageService.forICloud(ref.watch(icloudServiceProvider).icloudPath),
);

final authProvider = FutureProvider<AuthSession?>(
  (ref) => ref.watch(authStorageServiceProvider).load(),
);

final activeTabProvider = StateProvider<AppTab>((_) => AppTab.projects);

/// Current settings, loaded from `~/.edithub/settings.json`.
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsServiceProvider).load();

  void update(AppSettings Function(AppSettings) mutate) {
    state = ref.read(settingsServiceProvider).update(mutate);
    // Re-scan with the new projects folder.
    ref.invalidate(projectsProvider);
  }
}

/// True while iCloud looks busy uploading archived projects. Polls a shallow
/// mtime check (year/month/project level) rather than a full recursive scan.
final icloudSyncingProvider = StreamProvider<bool>((ref) {
  final icloud = ref.watch(icloudServiceProvider);
  bool busy() => icloud.getUploadingProjects().isNotEmpty;
  return Stream<bool>.multi((controller) {
    controller.add(busy());
    final timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => controller.add(busy()),
    );
    controller.onCancel = timer.cancel;
  });
});

/// Hourly auto-offload of stale / past-month projects to iCloud. Started by
/// being watched once at app boot; first run is deferred by one interval so a
/// launch never triggers a surprise mass-move.
final autoArchiveProvider = Provider<void>((ref) {
  final timer = Timer.periodic(const Duration(hours: 1), (_) async {
    final settings = ref.read(settingsProvider);
    await ref
        .read(archiverServiceProvider)
        .runAutoArchive(
          projectsFolder: settings.projectsFolder,
          archiveFolder: ref.read(icloudServiceProvider).archiveFolder,
          autoArchiveDays: settings.autoArchiveDays,
        );
    ref.invalidate(projectsProvider);
  });
  ref.onDispose(timer.cancel);
});

/// Resumes downloads that were interrupted by a crash/quit: any project left
/// in `downloading` state on disk is restarted (the downloader picks up each
/// file from its `.part`). Paused projects are left alone — the user stopped
/// them on purpose. Watched once at app boot.
final downloadResumeProvider = Provider<void>((ref) {
  final handled = <String>{};
  ref.listen<AsyncValue<List<ProjectInfo>>>(projectsProvider, (_, next) {
    final projects = next.value;
    if (projects == null) return;
    final repo = ref.read(projectRepositoryProvider);
    for (final project in projects) {
      if (project.status == ProjectStatus.downloading &&
          project.footageUrls.isNotEmpty &&
          project.folderPath != null &&
          !repo.isDownloading(project.id) &&
          handled.add(project.id)) {
        repo.resumeDownload(project, (_) => ref.invalidate(projectsProvider));
      }
    }
  }, fireImmediately: true);
});

/// Projects scanned from the configured projects folder.
///
/// Two-phase so first launch isn't blocked on iCloud: the local folder scan
/// (fast) is emitted immediately, then the iCloud archive migration + scan
/// (slow on cold start — isolate spawn + on-demand placeholder files) runs off
/// the first-paint path and the combined list is emitted when it's ready.
final projectsProvider = StreamProvider<List<ProjectInfo>>((ref) async* {
  final settings = ref.watch(settingsProvider);
  final store = ref.read(projectStoreProvider);
  final icloud = ref.watch(icloudServiceProvider);

  final local = store.listProjects(settings.projectsFolder);
  yield local;

  await Isolate.run(() => ICloudService.prepareArchiveAt(icloud.icloudPath));
  final projects = [...local];
  final seen = projects.map((project) => project.id).toSet();
  for (final archived in icloud.archiveSearchFolders) {
    projects.addAll(
      store
          .listArchivedProjects(archived)
          .where((project) => seen.add(project.id)),
    );
  }
  yield projects;
});
