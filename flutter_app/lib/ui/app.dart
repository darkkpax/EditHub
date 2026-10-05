import 'dart:io';

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
    _initTray();
  }

  Future<void> _initTray() async {
    try {
      await windowManager.setPreventClose(true);
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip('EditHub');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'open', label: 'Open EditHub'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Quit'),
          ],
        ),
      );
    } catch (error) {
      debugPrint('Tray initialization failed: $error');
    }
  }

  Future<void> _openApp() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() => windowManager.hide();

  // The OS draws a separate menu; the main window keeps its size and position.
  @override
  void onTrayIconMouseDown() => trayManager.popUpContextMenu();
  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem item) {
    if (item.key == 'open') _openApp();
    if (item.key == 'quit') trayManager.destroy().whenComplete(() => exit(0));
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authProvider);
    ref.watch(downloadResumeProvider);
    final tab = ref.watch(activeTabProvider);
    return Scaffold(
      backgroundColor: AppColors.of(context).bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: switch (tab) {
              AppTab.projects => ProjectsScreen(),
              AppTab.settings => SettingsScreen(),
            },
          ),
          Positioned(top: 0, left: 0, right: 0, child: AppTabBar()),
        ],
      ),
    );
  }
}
