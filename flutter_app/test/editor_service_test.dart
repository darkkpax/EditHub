import 'dart:io';

import 'package:edithub/services/editor_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Premiere launch targets an existing project before the executable', () {
    final root = Directory.systemTemp.createTempSync('edithub_editor_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final project = File('${root.path}${Platform.pathSeparator}cut.prproj')
      ..writeAsStringSync('template');

    expect(findPremiereProject(root.path), project.path);
  });
}
