import 'dart:async';
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
  '/FORCECLOSEAPPLICATIONS',
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
  UpdaterService([this.navigatorKey]);
  final GlobalKey<NavigatorState>? navigatorKey;
  bool _prompting = false;
  Timer? _timer;

  void start() {
    if (!kReleaseMode || !Platform.isWindows) return;
    check();
    _timer ??= Timer.periodic(const Duration(hours: 6), (_) => check());
  }

  void dispose() => _timer?.cancel();

  Future<void> check({BuildContext? context, bool interactive = false}) async {
    if (_prompting) return;
    _prompting = true;
    final target = context ?? navigatorKey?.currentContext;
    try {
      final res = await http
          .get(Uri.parse(_feedUrl))
          .timeout(Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw HttpException('Update server returned HTTP ${res.statusCode}.');
      }
      final latest = parseAppcast(res.body);
      if (latest == null) {
        throw const FormatException('The update feed has no installer.');
      }
      final current = (await PackageInfo.fromPlatform()).version;
      if (!isNewerVersion(latest.version, current)) {
        if (interactive && target != null && target.mounted) {
          ScaffoldMessenger.of(target).showSnackBar(
            SnackBar(content: Text('EditHub $current is up to date.')),
          );
        }
        return;
      }

      if (target == null || !target.mounted) return;
      await showDialog<void>(
        context: target,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: .45),
        builder: (_) => _UpdateDialog(version: latest.version, url: latest.url),
      );
    } catch (error) {
      debugPrint('Update check failed: $error');
      if (interactive && target != null && target.mounted) {
        ScaffoldMessenger.of(target).showSnackBar(
          SnackBar(content: Text('Could not check for updates: $error')),
        );
      }
    } finally {
      _prompting = false;
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
          _error = 'Update failed: $error';
          _progress = null;
        });
      }
    }
  }

  Future<File> _download(String url, ValueChanged<double> onProgress) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        !uri.path.startsWith('/darkkpax/EditHub/releases/download/')) {
      throw const FormatException(
        'The installer URL is not an EditHub GitHub release.',
      );
    }
    final req = http.Request('GET', uri);
    final res = await req.send().timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
    }
    final dir = await Directory.systemTemp.createTemp('edithub_update');
    final file = File(p.join(dir.path, p.basename(Uri.parse(url).path)));
    final sink = file.openWrite();
    final total = res.contentLength ?? 0;
    var received = 0;
    try {
      await for (final chunk in res.stream.timeout(
        const Duration(seconds: 45),
      )) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
    } finally {
      await sink.close();
    }
    if (received == 0 || (total > 0 && received != total)) {
      throw const HttpException(
        'Installer download is incomplete. Retry the update.',
      );
    }
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
                        color: AppColors.of(
                          context,
                        ).accent.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.rocket_launch_rounded,
                        color: AppColors.of(context).accent,
                        size: 20,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Update available',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Version ${widget.version}',
                            style: TextStyle(
                              color: AppColors.of(context).dim,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  SizedBox(height: 14),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: AppColors.of(context).bad,
                      fontSize: 12,
                    ),
                  ),
                ],
                SizedBox(height: 18),
                if (downloading)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress,
                      minHeight: 8,
                      backgroundColor: AppColors.of(context).fill4,
                    ),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Later',
                          style: TextStyle(color: AppColors.of(context).dim),
                        ),
                      ),
                      SizedBox(width: 8),
                      FilledButton(onPressed: _install, child: Text('Install')),
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
