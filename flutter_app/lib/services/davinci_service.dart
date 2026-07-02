import 'dart:io';

import 'package:path/path.dart' as p;

class LaunchDaVinciResult {
  final bool launched;
  final bool projectReady;
  final String? message;
  final String? drpFilePath;
  LaunchDaVinciResult({
    required this.launched,
    required this.projectReady,
    this.message,
    this.drpFilePath,
  });
}

/// Launches DaVinci Resolve and opens/exports a project via the bundled
/// `resolve_project_bridge.py` script. Mirrors `davinci.ts`.
class DaVinciService {
  static const _defaultWin =
      r'C:\Program Files\Blackmagic Design\DaVinci Resolve\Resolve.exe';

  static String autoDetect() {
    final pf = Platform.environment['ProgramFiles'];
    final pfx86 = Platform.environment['ProgramFiles(x86)'];
    final candidates = <String>[
      _defaultWin,
      r'C:\Program Files (x86)\Blackmagic Design\DaVinci Resolve\Resolve.exe',
      if (pf != null)
        p.join(pf, 'Blackmagic Design', 'DaVinci Resolve', 'Resolve.exe'),
      if (pfx86 != null)
        p.join(pfx86, 'Blackmagic Design', 'DaVinci Resolve', 'Resolve.exe'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return _defaultWin;
  }

  bool isResolveRunning() {
    try {
      final result = Process.runSync('tasklist', [
        '/FI',
        'IMAGENAME eq Resolve.exe',
        '/NH',
      ]);
      return result.stdout.toString().toLowerCase().contains('resolve.exe');
    } catch (_) {
      return false;
    }
  }

  String? _findBridgeScript() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    for (final c in [
      p.join(
        exeDir,
        'data',
        'flutter_assets',
        'assets',
        'resolve_project_bridge.py',
      ),
      p.join(exeDir, 'assets', 'resolve_project_bridge.py'),
    ]) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  List<String>? _findScriptRunner() {
    for (final c in [
      r'C:\Program Files\Blackmagic Design\DaVinci Resolve\fuscript.exe',
      r'C:\Program Files (x86)\Blackmagic Design\DaVinci Resolve\fuscript.exe',
    ]) {
      if (File(c).existsSync()) return [c];
    }
    for (final c in ['python', 'py', 'python3']) {
      try {
        final r = Process.runSync(c, ['--version']);
        if (r.exitCode == 0) return [c];
      } catch (_) {}
    }
    return null;
  }

  Future<String> _runBridge(
    String action,
    String projectFolder,
    String drpFilePath,
  ) async {
    final script = _findBridgeScript();
    if (script == null) {
      throw Exception('Resolve bridge script not found');
    }
    final runner = _findScriptRunner();
    if (runner == null) {
      throw Exception('DaVinci Resolve script runner not found');
    }

    final result = await Process.run(runner.first, [
      ...runner.skip(1),
      script,
      '--action',
      action,
      '--project-name',
      p.basename(projectFolder),
      '--project-folder',
      projectFolder,
      '--drp-path',
      drpFilePath,
      '--timeout',
      '45',
    ]).timeout(const Duration(seconds: 60));

    if (result.exitCode == 0) return result.stdout.toString().trim();
    throw Exception(
      (result.stderr.toString().isNotEmpty ? result.stderr : result.stdout)
          .toString()
          .trim(),
    );
  }

  Future<LaunchDaVinciResult> launch(
    String davinciPath,
    String projectFolder,
  ) async {
    final resolvePath = davinciPath.isNotEmpty ? davinciPath : autoDetect();
    if (!File(resolvePath).existsSync()) {
      return LaunchDaVinciResult(
        launched: false,
        projectReady: false,
        message: 'DaVinci Resolve not found',
      );
    }
    final drpFilePath = p.join(
      projectFolder,
      '${p.basename(projectFolder)}.drp',
    );
    try {
      if (!isResolveRunning()) {
        await Process.start(resolvePath, [], mode: ProcessStartMode.detached);
        await Future.delayed(const Duration(seconds: 3));
      }
      final message = await _runBridge('open', projectFolder, drpFilePath);
      return LaunchDaVinciResult(
        launched: true,
        projectReady: true,
        message: message,
        drpFilePath: drpFilePath,
      );
    } catch (e) {
      return LaunchDaVinciResult(
        launched: true,
        projectReady: false,
        message: e.toString(),
        drpFilePath: drpFilePath,
      );
    }
  }

  Future<({bool exported, String? message, String drpFilePath})> export(
    String projectFolder,
  ) async {
    final drpFilePath = p.join(
      projectFolder,
      '${p.basename(projectFolder)}.drp',
    );
    try {
      final message = await _runBridge('export', projectFolder, drpFilePath);
      return (exported: true, message: message, drpFilePath: drpFilePath);
    } catch (e) {
      return (exported: false, message: e.toString(), drpFilePath: drpFilePath);
    }
  }
}
