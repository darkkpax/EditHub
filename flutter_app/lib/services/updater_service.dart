import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../theme.dart';
import '../ui/design/glass_surface.dart';

/// Stable appcast: `releases/latest/download/appcast.xml` always resolves to
/// the newest published release's asset.
const _feedUrl =
    'https://github.com/darkkpax/EditHub/releases/latest/download/appcast.xml';

const installerArguments = [
  '/VERYSILENT',
  '/NORESTART',
  '/RESTARTAPPLICATIONS',
];

/// The newest published version + its installer URL, pulled from the appcast.
({String version, String url})? parseAppcast(String xml) {
  final url = RegExp(r'url="([^"]+\.exe)"').firstMatch(xml)?.group(1);
  final version =
      RegExp(r'sparkle:version="([^"]+)"').firstMatch(xml)?.group(1) ??
      RegExp(r'<sparkle:version>([^<]+)</').firstMatch(xml)?.group(1);
  if (url == null || version == null) return null;
  return (version: version, url: url);
}

/// Numeric-segment compare: is [latest] a higher version than [current]?
bool isNewerVersion(String latest, String current) {
  int seg(String s, int i) {
    final parts = s.split('.');
    if (i >= parts.length) return 0;
    return int.tryParse(parts[i].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  for (var i = 0; i < 3; i++) {
    final a = seg(latest, i), b = seg(current, i);
    if (a != b) return a > b;
  }
  return false;
}

/// In-app updater that shows an app-styled prompt instead of WinSparkle's
/// native dialog. Release builds only; no-op elsewhere.
class UpdaterService {
  UpdaterService(this.navigatorKey);
  final GlobalKey<NavigatorState> navigatorKey;
  bool _prompting = false;

  void start() {
    if (!kReleaseMode || !Platform.isWindows) return;
    _check();
    // Re-check every 6h for long-running sessions.
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(hours: 6));
      await _check();
      return true;
    });
  }

  Future<void> _check() async {
    if (_prompting) return;
    try {
      final res = await http
          .get(Uri.parse(_feedUrl))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return;
      final latest = parseAppcast(res.body);
      if (latest == null) return;
      final current = (await PackageInfo.fromPlatform()).version;
      if (!isNewerVersion(latest.version, current)) return;

      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      _prompting = true;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .45),
        builder: (_) => _UpdateDialog(version: latest.version, url: latest.url),
      );
      _prompting = false;
    } catch (_) {
      _prompting = false; // never let an update check crash the app
    }
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.version, required this.url});
  final String version;
  final String url;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress; // null until the user starts downloading
  String? _error;

  Future<void> _install() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final file = await _download(widget.url, (p) {
        if (mounted) setState(() => _progress = p);
      });
      // Silent in-place upgrade; the installer closes the running app itself.
      await Process.start(
        file.path,
        installerArguments,
        mode: ProcessStartMode.detached,
      );
      exit(0);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Не удалось обновить: $error';
          _progress = null;
        });
      }
    }
  }

  Future<File> _download(String url, ValueChanged<double> onProgress) async {
    final req = http.Request('GET', Uri.parse(url));
    final res = await req.send();
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
    }
    final dir = await Directory.systemTemp.createTemp('edithub_update');
    final file = File(p.join(dir.path, p.basename(Uri.parse(url).path)));
    final sink = file.openWrite();
    final total = res.contentLength ?? 0;
    var received = 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
    }
    await sink.close();
    return file;
  }

  @override
  Widget build(BuildContext context) {
    final downloading = _progress != null;
    return Center(
      child: SizedBox(
        width: 340,
        child: GlassSurface(
          blur: 24,
          radius: 22,
          scrim: .5,
          frost: .1,
          shadow: true,
          padding: const EdgeInsets.all(20),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.rocket_launch_rounded,
                        color: AppColors.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Доступно обновление',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Версия ${widget.version}',
                            style: const TextStyle(
                              color: AppColors.dim,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.bad, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 18),
                if (downloading)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress,
                      minHeight: 8,
                      backgroundColor: const Color(0x22FFFFFF),
                    ),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Позже',
                          style: TextStyle(color: AppColors.dim),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _install,
                        child: const Text('Установить'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
