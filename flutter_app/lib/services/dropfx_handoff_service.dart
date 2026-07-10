import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/models.dart';

/// Writes the currently open project to a shared file that DropFX reads, so a
/// sound dragged out of DropFX lands in this project's SFX folder.
///
/// This is the entire link between EditHub and DropFX — one small JSON file.
/// No shared process, no hardcoded paths in either app.
///
/// ponytail: plain file write, best-effort. DropFX polls it. If it ever needs
/// to be instant, swap the file for a localhost socket on both sides.
class DropFXHandoffService {
  static String get _home =>
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;

  static File get _file =>
      File(p.join(_home, '.edithub', 'active_project.json'));

  void setActive(ProjectInfo project) {
    final path = project.folderPath;
    if (path == null || path.isEmpty) return;
    try {
      final f = _file;
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode({
        'name': project.name,
        'folderPath': path,
      }));
    } catch (_) {
      // Best-effort: never let handoff break project switching.
    }
  }
}
