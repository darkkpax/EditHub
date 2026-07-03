import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'services/project_store.dart';
import 'services/settings_service.dart';
import 'services/updater_service.dart';
import 'theme.dart';
import 'ui/app.dart';
import 'window_config.dart';

// ponytail: fixed loopback port as a single-instance lock. Only the first
// instance can bind it; later launches connect (nudging the primary to show)
// and exit before creating a second tray icon. Upgrade to a native mutex only
// if this port ever clashes with something on the user's machine.
const _kSingleInstancePort = 47615;

/// Returns true if this is the primary instance. Secondary instances signal
/// the primary to surface, then get false and should exit immediately.
Future<bool> _claimSingleInstance() async {
  try {
    final server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, _kSingleInstancePort);
    server.listen((socket) async {
      socket.destroy();
      await windowManager.show();
      await windowManager.focus();
    });
    return true;
  } on SocketException {
    try {
      (await Socket.connect(InternetAddress.loopbackIPv4, _kSingleInstancePort))
          .destroy();
    } catch (_) {}
    return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Already running? Bring the existing window forward and quit this launch
  // so the tray isn't populated twice.
  if (!await _claimSingleInstance()) {
    exit(0);
  }

  // Sweep orphaned `__extracting_*` temp folders left by interrupted
  // extractions before the UI touches anything.
  try {
    final settings = SettingsService().load();
    ProjectStore().sweepExtractingDirs([
      settings.projectsFolder,
      '${settings.icloudPath}\\Videos',
    ]);
  } catch (_) {}

  const options = WindowOptions(
    size: kEditHubWindowSize,
    minimumSize: kEditHubMinimumSize,
    center: true,
    backgroundColor: AppColors.bg,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'EditHub',
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
    await initAutoUpdater();
  });

  runApp(const ProviderScope(child: EditHubRoot()));
}

class EditHubRoot extends StatelessWidget {
  const EditHubRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EditHub',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const EditHubApp(),
    );
  }
}
