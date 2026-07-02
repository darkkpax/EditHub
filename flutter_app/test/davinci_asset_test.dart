import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DaVinci bridge is bundled as a Flutter asset', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/resolve_project_bridge.py'));
    expect(File('assets/resolve_project_bridge.py').existsSync(), isTrue);
  });
}
