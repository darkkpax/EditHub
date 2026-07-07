import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/providers.dart';
import '../theme.dart';
import '../window_config.dart';
import 'design/motion.dart';
import 'tab_bar.dart';
import 'screens/projects_screen.dart';
import 'screens/settings_screen.dart';

// Size of the custom tray popup (in place of the native Win32 menu).
const kTrayMenuSize = Size(176, 72);

class EditHubApp extends ConsumerStatefulWidget {
  const EditHubApp({super.key});

  @override
  ConsumerState<EditHubApp> createState() => _EditHubAppState();
}

class _EditHubAppState extends ConsumerState<EditHubApp>
    with WindowListener, TrayListener {
  // While true the single window shrinks to a small cursor-anchored menu.
  bool _trayMenu = false;

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
    // No native context menu — we draw our own app-styled popup (below).
  }

  Future<void> _openApp() async {
    if (_trayMenu) setState(() => _trayMenu = false);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setMinimumSize(kEditHubMinimumSize);
    await windowManager.setSize(kEditHubWindowSize);
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    await trayManager.destroy();
    exit(0);
  }

  /// Show the app-styled menu as a small window anchored above the cursor.
  Future<void> _showTrayMenu() async {
    try {
      final cursor = await screenRetriever.getCursorScreenPoint();
      final w = kTrayMenuSize.width, h = kTrayMenuSize.height;
      final x = (cursor.dx - w).clamp(8.0, double.infinity);
      final y = (cursor.dy - h - 8).clamp(8.0, double.infinity);
      setState(() => _trayMenu = true);
      await windowManager.setMinimumSize(const Size(0, 0));
      await windowManager.setSize(kTrayMenuSize);
      await windowManager.setPosition(Offset(x, y));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {
      // If positioning fails for any reason, fall back to opening the app.
      await _openApp();
    }
  }

  Future<void> _dismissTrayMenu() async {
    if (!_trayMenu) return;
    setState(() => _trayMenu = false);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setMinimumSize(kEditHubMinimumSize);
    await windowManager.setSize(kEditHubWindowSize);
    await windowManager.hide();
  }

  @override
  void onWindowClose() {
    // Prevented close -> hide to tray.
    windowManager.hide();
  }

  @override
  void onWindowBlur() {
    // Tapping elsewhere closes the tray popup, like a real menu.
    if (_trayMenu) _dismissTrayMenu();
  }

  @override
  void onTrayIconMouseDown() => _openApp();

  @override
  void onTrayIconRightMouseDown() => _showTrayMenu();

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

    if (_trayMenu) {
      return _TrayMenu(onOpen: _openApp, onQuit: _quit);
    }

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

/// App-styled replacement for the native tray context menu.
class _TrayMenu extends StatelessWidget {
  const _TrayMenu({required this.onOpen, required this.onQuit});
  final VoidCallback onOpen;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.card,
      body: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TrayItem(
              icon: Icons.open_in_full_rounded,
              label: 'Open EditHub',
              onTap: onOpen,
            ),
            _TrayItem(
              icon: Icons.power_settings_new_rounded,
              label: 'Quit',
              onTap: onQuit,
              danger: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrayItem extends StatefulWidget {
  const _TrayItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_TrayItem> createState() => _TrayItemState();
}

class _TrayItemState extends State<_TrayItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.danger ? AppColors.bad : AppColors.txt;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: PressableScale(
        onTap: widget.onTap,
        pressedScale: .97,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hover
                ? (widget.danger
                      ? AppColors.bad.withValues(alpha: .18)
                      : const Color(0x1FFFFFFF))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 15, color: color),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
