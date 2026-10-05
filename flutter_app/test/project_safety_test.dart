import 'dart:io';

import 'package:edithub/models/models.dart';
import 'package:edithub/services/archiver_service.dart';
import 'package:edithub/services/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'project deletion refuses the storage root and unrelated folders',
    () async {
      final root = Directory.systemTemp.createTempSync('edithub_delete_guard_');
      addTearDown(() => root.deleteSync(recursive: true));
      final store = ProjectStore();
      await expectLater(
        store.deleteProject(root.path, roots: [root.path]),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        store.deleteProject(root.parent.path, roots: [root.path]),
        throwsA(isA<FileSystemException>()),
      );
      expect(root.existsSync(), isTrue);
    },
  );
  test(
    'offload preserves footage and restore keeps the cloud backup',
    () async {
      final root = Directory.systemTemp.createTempSync('edithub_safety_');
      addTearDown(() => root.deleteSync(recursive: true));
      final store = ProjectStore();
      final folder = p.join(root.path, 'local', '2026', 'SEPTEMBER', 'Film');
      Directory(p.join(folder, 'FOOTAGE')).createSync(recursive: true);
      File(p.join(folder, 'FOOTAGE', 'raw.mov')).writeAsStringSync('original');
      store.writeProjectInfo(
        folder,
        ProjectInfo(
          id: 'film',
          name: 'Film',
          year: '2026',
          month: 'SEPTEMBER',
          createdAt: '2026-09-01',
          lastOpenedAt: '2026-09-01',
        ),
      );
      final archiver = ArchiverService(store);
      final cloud = p.join(root.path, 'cloud');
      await archiver.archiveProject(
        folder,
        cloud,
        sourceRoot: p.join(root.path, 'local'),
      );
      final archive = p.join(cloud, '2026', 'SEPTEMBER', 'Film');
      expect(
        File(p.join(archive, 'FOOTAGE', 'raw.mov')).readAsStringSync(),
        'original',
      );
      final restored = await archiver.restoreFromArchive(
        archive,
        p.join(root.path, 'local'),
      );
      expect(
        File(p.join(restored, 'FOOTAGE', 'raw.mov')).readAsStringSync(),
        'original',
      );
      expect(Directory(archive).existsSync(), isTrue);
    },
  );
}
