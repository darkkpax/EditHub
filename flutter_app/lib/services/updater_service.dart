import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';

/// Stable appcast URL: `releases/latest/download/<asset>` always resolves to
/// the newest published release's asset, so the app never needs a new feed URL.
const _feedUrl =
    'https://github.com/darkkpax/EditHub/releases/latest/download/appcast.xml';

/// Wires WinSparkle auto-update. No-op in debug (WinSparkle expects an
/// installed, versioned build) and off Windows.
Future<void> initAutoUpdater() async {
  if (!kReleaseMode || !Platform.isWindows) return;
  try {
    await autoUpdater.setFeedURL(_feedUrl);
    await autoUpdater.setScheduledCheckInterval(6 * 3600); // every 6h
    await autoUpdater.checkForUpdates(inBackground: true);
  } catch (_) {
    // Never let an update check block startup.
  }
}
