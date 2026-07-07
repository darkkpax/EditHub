import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/models.dart';

/// Reads/writes the same `~/.edithub/settings.json` the Electron app used,
/// so an existing install keeps its configuration after the migration.
class SettingsService {
  static String get _home =>
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;

  static String get _settingsPath => p.join(_home, '.edithub', 'settings.json');

  static AppSettings get defaults => AppSettings(
    projectsFolder: p.join(_home, 'EditHub', 'Projects'),
    downloadsFolder: p.join(_home, 'Downloads'),
    dropfxLibrary: p.join(_home, 'EditHub', 'SFX'),
    davinciPath:
        r'C:\Program Files\Blackmagic Design\DaVinci Resolve\Resolve.exe',
    premierePath:
        r'C:\Program Files\Adobe\Adobe Premiere Pro 2026\Adobe Premiere Pro.exe',
    autoArchiveDays: 30,
    autoImportPatterns: const ['*-enhanced*', '*-enhanced-v2*'],
    icloudPath: p.join(_home, 'iCloudDrive'),
  );

  AppSettings load() {
    try {
      final file = File(_settingsPath);
      if (file.existsSync()) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        return AppSettings.fromJson(json, defaults);
      }
    } catch (_) {}
    return defaults;
  }

  void save(AppSettings settings) {
    try {
      final file = File(_settingsPath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      );
    } catch (e) {
      // ignore: avoid_print
      print('Failed to save settings: $e');
    }
  }

  AppSettings update(AppSettings Function(AppSettings current) mutate) {
    final updated = mutate(load());
    save(updated);
    return updated;
  }
}
