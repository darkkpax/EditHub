import 'dart:io';

import 'package:edithub/models/models.dart';
import 'package:edithub/services/project_store.dart';
import 'package:edithub/services/shell_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('folder size is computed on demand, not during scan', () {
    final root = Directory.systemTemp.createTempSync('edithub_size_');
    addTearDown(() => root.deleteSync(recursive: true));
    final folder = Directory(p.join(root.path, '2026', 'JUNE', 'Sized project'))
      ..createSync(recursive: true);
    final store = ProjectStore();
    store.writeProjectInfo(
      folder.path,
      ProjectInfo(
        id: 'sized',
        name: 'Sized project',
        year: '2026',
        month: 'JUNE',
        createdAt: '2026-06-01T00:00:00Z',
        lastOpenedAt: '2026-06-01T00:00:00Z',
      ),
    );
    File(
      p.join(folder.path, 'clip.bin'),
    ).writeAsBytesSync(List.filled(1536, 1));

    final project = store.listProjects(root.path).single;

    // Scan stays cheap: it does not walk the tree for a size.
    expect(project.sizeBytes, isNull);
    // Size is available on demand via the dedicated call.
    expect(store.getFolderSizeBytes(folder.path), greaterThanOrEqualTo(1536));
  });

  test('project without a manifest keeps its month category', () {
    final root = Directory.systemTemp.createTempSync('edithub_period_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(
      p.join(root.path, '2026', 'JULY', 'Plain project', 'Media', 'FOOTAGE'),
    ).createSync(recursive: true);

    final project = ProjectStore().listProjects(root.path).single;

    expect(project.name, 'Plain project');
    expect(project.year, '2026');
    expect(project.month, 'JULY');
  });

  test('Explorer arguments open folders and select files', () {
    expect(explorerArguments(r'D:\Videos\Project'), [r'D:\Videos\Project']);
    expect(explorerArguments(r'D:\Videos\Project\clip.mov', selectFile: true), [
      '/select,',
      r'D:\Videos\Project\clip.mov',
    ]);
  });
}
