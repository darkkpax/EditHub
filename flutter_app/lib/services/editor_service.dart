import 'dart:io';

import 'package:path/path.dart' as p;

String? findPremiereProject(String folder) {
  try {
    return Directory(folder)
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .map((file) => file.path)
        .firstWhere((path) => p.extension(path).toLowerCase() == '.prproj');
  } on StateError {
    return null;
  }
}

class EditorService {
  static const defaultPremierePath =
      r'C:\Program Files\Adobe\Adobe Premiere Pro 2026\Adobe Premiere Pro.exe';

  Future<void> launchPremiere(String configuredPath, String folder) async {
    final project = findPremiereProject(folder);
    if (project != null) {
      await Process.start('cmd', [
        '/c',
        'start',
        '',
        project,
      ], mode: ProcessStartMode.detached);
      return;
    }
    final executable = configuredPath.isEmpty
        ? defaultPremierePath
        : configuredPath;
    if (!File(executable).existsSync()) {
      throw Exception(
        'Adobe Premiere Pro not found. Set its path in Settings.',
      );
    }
    await Process.start(executable, [], mode: ProcessStartMode.detached);
  }
}
