import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'services/project_store.dart';
import 'services/settings_service.dart';
import 'services/updater_service.dart';
import 'theme.dart';
import 'ui/app.dart';
import 'window_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

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
