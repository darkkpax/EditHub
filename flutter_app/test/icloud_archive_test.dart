import 'dart:io';

import 'package:edithub/models/models.dart';
import 'package:edithub/services/archiver_service.dart';
import 'package:edithub/services/icloud_service.dart';
import 'package:edithub/services/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('migrates legacy archives into edithub Videos year MM', () {
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
      Directory(p.join(archive, '2025', '06', 'Old project')).existsSync(),
      isTrue,
    );
    expect(ProjectStore().listArchivedProjects(archive), hasLength(1));
  });

  test('new archives use a numeric month folder', () async {
    final root = Directory.systemTemp.createTempSync('edithub_archive_');
    addTearDown(() => root.deleteSync(recursive: true));
    final project = Directory(p.join(root.path, 'local', 'Project'))
      ..createSync(recursive: true);
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

    expect(
      Directory(
        p.join(root.path, 'edithub', 'Videos', '2026', '07', 'Project'),
      ).existsSync(),
      isTrue,
    );
  });
}
