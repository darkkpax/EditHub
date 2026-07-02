import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/providers.dart';
import '../theme.dart';
import 'tab_bar.dart';
import 'screens/projects_screen.dart';
import 'screens/settings_screen.dart';

class EditHubApp extends ConsumerStatefulWidget {
  const EditHubApp({super.key});

  @override
  ConsumerState<EditHubApp> createState() => _EditHubAppState();
}

class _EditHubAppState extends ConsumerState<EditHubApp>
    with WindowListener, TrayListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    _initTrayAndClose();
  }

  Future<void> _initTrayAndClose() async {
    // Close hides to tray instead of quitting (matches the old app).
    await windowManager.setPreventClose(true);
    await trayManager.setIcon('assets/tray_icon.ico');
    await trayManager.setToolTip('EditHub');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Open EditHub'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() {
    // Prevented close -> hide to tray.
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      _show();
    } else if (menuItem.key == 'quit') {
      windowManager.setPreventClose(false).then((_) => windowManager.destroy());
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Initializes/reads iCloud Drive/EditHub/auth.json in the background.
    // Missing credentials never block the local application shell.
    ref.watch(authProvider);
    // Start the hourly auto-offload timer for its lifetime.
    ref.watch(autoArchiveProvider);

    final tab = ref.watch(activeTabProvider);
    // Tab bar floats over the content (Stack, not Column) so the content flows
    // under its frosted glass — no hard divider seam, and the blur has
    // something to work on, like the sidebar's search header.
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: switch (tab) {
              AppTab.projects => const ProjectsScreen(),
              AppTab.settings => const SettingsScreen(),
            },
          ),
          const Positioned(top: 0, left: 0, right: 0, child: AppTabBar()),
        ],
      ),
    );
  }
}
