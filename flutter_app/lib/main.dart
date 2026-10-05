import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'services/updater_service.dart';
import 'theme.dart';
import 'state/providers.dart';
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
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      _kSingleInstancePort,
    );
    server.listen((socket) async {
      socket.destroy();
      await windowManager.show();
      await windowManager.focus();
    });
    return true;
  } on SocketException {
    try {
      (await Socket.connect(
        InternetAddress.loopbackIPv4,
        _kSingleInstancePort,
      )).destroy();
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
  });

  runApp(const ProviderScope(child: EditHubRoot()));
}

final _navigatorKey = GlobalKey<NavigatorState>();

class EditHubRoot extends ConsumerStatefulWidget {
  const EditHubRoot({super.key});

  @override
  ConsumerState<EditHubRoot> createState() => _EditHubRootState();
}

class _EditHubRootState extends ConsumerState<EditHubRoot> {
  late final _updater = UpdaterService(_navigatorKey);
  @override
  void initState() {
    super.initState();
    // Check for updates once the navigator exists (styled in-app prompt).
    WidgetsBinding.instance.addPostFrameCallback((_) => _updater.start());
  }

  @override
  void dispose() {
    _updater.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EditHub',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness: Brightness.light),
      darkTheme: buildTheme(),
      themeMode: switch (ref.watch(settingsProvider).theme) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      // Hide scrollbars app-wide (scrolling still works, drag/wheel unaffected).
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      home: const EditHubApp(),
    );
  }
}
