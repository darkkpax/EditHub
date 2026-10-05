import 'dart:io';

import 'package:edithub/models/models.dart';
import 'package:edithub/state/providers.dart';
import 'package:edithub/theme.dart';
import 'package:edithub/ui/screens/projects_screen.dart';
import 'package:edithub/ui/tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final font in {
      'Nunito Sans': 'NunitoSans.ttf',
      'Newsreader': 'Newsreader.ttf',
      'UnifrakturCook': 'UnifrakturCook-Bold.ttf',
    }.entries) {
      await (FontLoader(
        font.key,
      )..addFont(rootBundle.load('assets/fonts/${font.value}'))).load();
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('project workspace is readable in ${brightness.name} theme', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1152, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory.systemTemp.createTempSync('edithub_preview_');
      addTearDown(() => root.deleteSync(recursive: true));
      final folder = Directory('${root.path}/Film')..createSync();
      for (final name in ['FOOTAGE', 'READY VIDEOS', 'MUSIC', 'SFX', 'DOCS']) {
        Directory('${folder.path}/$name').createSync();
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectsProvider.overrideWith(
              (_) => Stream.value([
                ProjectInfo(
                  id: 'film',
                  name: 'The midnight procession',
                  year: '2026',
                  month: 'OCTOBER',
                  createdAt: '2026-10-01',
                  lastOpenedAt: '2026-10-05',
                  folderPath: folder.path,
                ),
                ProjectInfo(
                  id: 'abbey',
                  name: 'Stone & silence',
                  year: '2026',
                  month: 'SEPTEMBER',
                  createdAt: '2026-09-01',
                  lastOpenedAt: '2026-09-10',
                  status: ProjectStatus.archive,
                ),
              ]),
            ),
            icloudSyncingProvider.overrideWith((_) => Stream.value(false)),
          ],
          child: MaterialApp(
            theme: buildTheme(brightness: brightness),
            home: Scaffold(
              body: RepaintBoundary(
                key: const Key('workspace-preview'),
                child: ColoredBox(
                  color: AppPalette(brightness).bg,
                  child: const Stack(
                    children: [
                      Positioned.fill(child: ProjectsScreen()),
                      Positioned(top: 0, left: 0, right: 0, child: AppTabBar()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('The midnight procession'), findsNWidgets(2));
      expect(
        Theme.of(tester.element(find.byType(ProjectsScreen))).brightness,
        brightness,
      );
      if (Platform.environment['EDITHUB_PREVIEW'] == '1') {
        await expectLater(
          find.byKey(const Key('workspace-preview')),
          matchesGoldenFile('goldens/workspace-${brightness.name}.png'),
        );
      }
    });
  }
}
