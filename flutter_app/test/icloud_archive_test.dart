import 'dart:io';

import 'package:edithub/models/models.dart';
import 'package:edithub/services/archiver_service.dart';
import 'package:edithub/services/icloud_service.dart';
import 'package:edithub/services/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('resolving the archive path does no startup migration work', () {
    final cloud = Directory.systemTemp.createTempSync('edithub_startup_');
    addTearDown(() => cloud.deleteSync(recursive: true));
    final legacy = Directory(p.join(cloud.path, 'Videos', '2025', 'JUNE'))
      ..createSync(recursive: true);

    final archive = ICloudService.archiveFolderAt(cloud.path);

    expect(archive, p.join(cloud.path, 'edithub', 'Videos'));
    expect(legacy.existsSync(), isTrue);
    expect(Directory(archive).existsSync(), isFalse);
  });

  test('migrates legacy archives into uppercase month folders', () {
    final cloud = Directory.systemTemp.createTempSync('edithub_cloud_');
    addTearDown(() => cloud.deleteSync(recursive: true));
    final old = Directory(
      p.join(cloud.path, 'Videos', '2025', 'JUNE', 'Old project'),
    )..createSync(recursive: true);
    ProjectStore().writeProjectInfo(
      old.path,
      ProjectInfo(
        id: 'old',
        name: 'Old project',
        year: '2025',
        month: 'JUNE',
        createdAt: '2025-06-01T00:00:00Z',
        lastOpenedAt: '2025-06-01T00:00:00Z',
      ),
    );

    final archive = ICloudService.prepareArchiveAt(cloud.path);

    expect(
      Directory(p.join(archive, '2025', 'JUNE', 'Old project')).existsSync(),
      isTrue,
    );
    expect(ProjectStore().listArchivedProjects(archive), hasLength(1));
  });

  test('new archives remove footage and preserve everything else', () async {
    final root = Directory.systemTemp.createTempSync('edithub_archive_');
    addTearDown(() => root.deleteSync(recursive: true));
    final project = Directory(p.join(root.path, 'local', 'Project'))
      ..createSync(recursive: true);
    final footage = Directory(p.join(project.path, 'FOOTAGE'))
      ..createSync(recursive: true);
    File(p.join(footage.path, 'raw.mov')).writeAsStringSync('raw');
    final ready = Directory(p.join(project.path, 'READY VIDEOS'))
      ..createSync(recursive: true);
    File(p.join(ready.path, 'final.mp4')).writeAsStringSync('final');
    final store = ProjectStore();
    store.writeProjectInfo(
      project.path,
      ProjectInfo(
        id: 'project',
        name: 'Project',
        year: '2026',
        month: 'JULY',
        createdAt: '2026-07-01T00:00:00Z',
        lastOpenedAt: '2026-07-01T00:00:00Z',
      ),
    );

    await ArchiverService(
      store,
    ).archiveProject(project.path, p.join(root.path, 'edithub', 'Videos'));

    final archived = p.join(
      root.path,
      'edithub',
      'Videos',
      '2026',
      'JULY',
      'Project',
    );
    expect(Directory(archived).existsSync(), isTrue);
    expect(Directory(p.join(archived, 'FOOTAGE')).existsSync(), isFalse);
    expect(
      File(p.join(archived, 'READY VIDEOS', 'final.mp4')).readAsStringSync(),
      'final',
    );
    expect(File(p.join(archived, '.edithub.json')).existsSync(), isTrue);
  });
}
