import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../state/providers.dart';
import '../theme.dart';
import 'design/motion.dart';

/// Top bar: draggable window region + icon-only tabs + window controls.
/// Frosted, no divider line (per design).
class AppTabBar extends ConsumerWidget {
  const AppTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeTabProvider);
    final bar = SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 8),
          _TabButton(
            icon: Icons.folder_rounded,
            selected: active == AppTab.projects,
            tooltip: 'Projects',
            onTap: () =>
                ref.read(activeTabProvider.notifier).state = AppTab.projects,
          ),
          _TabButton(
            icon: Icons.settings_rounded,
            selected: active == AppTab.settings,
            tooltip: 'Settings',
            onTap: () =>
                ref.read(activeTabProvider.notifier).state = AppTab.settings,
          ),
          const Expanded(
            child: DragToMoveArea(child: SizedBox(height: double.infinity)),
          ),
          const _ICloudStatus(),
          const SizedBox(width: 6),
          const _WindowButton(icon: Icons.remove, kind: _WindowAction.minimize),
          const _WindowButton(
            icon: Icons.crop_square_rounded,
            kind: _WindowAction.maximize,
          ),
          const _WindowButton(
            icon: Icons.close_rounded,
            kind: _WindowAction.close,
          ),
        ],
      ),
    );
    // Fully transparent — no blur/fill of its own. The header glass beneath
    // (sidebar + detail headers, both 0..116) is the single surface across the
    // whole top strip, so the window controls sit on that one continuous glass
    // with no seam at the bar's bottom edge.
    return bar;
  }
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          width: 42,
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? AppColors.card2 : Colors.transparent,
            borderRadius: BorderRadius.circular(AppColors.radiusSm),
          ),
          child: AnimatedScale(
            scale: selected ? 1.08 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            child: Icon(
              icon,
              size: 20,
              color: selected ? AppColors.txt : AppColors.dim,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small iCloud sync indicator: a done-cloud when idle, a spinning ring over
/// the cloud while archived projects are uploading.
class _ICloudStatus extends ConsumerWidget {
  const _ICloudStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncing = ref.watch(icloudSyncingProvider).value ?? false;
    return Tooltip(
      message: syncing ? 'iCloud: uploading…' : 'iCloud: up to date',
      child: SizedBox(
        width: 30,
        height: 30,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              syncing ? Icons.cloud_queue_rounded : Icons.cloud_done_rounded,
              size: 18,
              color: syncing ? AppColors.accent : AppColors.dim,
            ),
            if (syncing)
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: AppColors.accent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _WindowAction { minimize, maximize, close }

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final _WindowAction kind;
  const _WindowButton({required this.icon, required this.kind});

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  Future<void> _run() async {
    switch (widget.kind) {
      case _WindowAction.minimize:
        await windowManager.minimize();
      case _WindowAction.maximize:
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      case _WindowAction.close:
        await windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isClose = widget.kind == _WindowAction.close;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: PressableScale(
        onTap: _run,
        pressedScale: .82,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: 46,
          height: 48,
          color: _hover
              ? (isClose
                    ? AppColors.bad.withValues(alpha: .85)
                    : AppColors.card2)
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 18,
            color: _hover && isClose ? Colors.white : AppColors.dim,
          ),
        ),
      ),
    );
  }
}
