import 'package:edithub/models/models.dart';
import 'package:edithub/state/providers.dart';
import 'package:edithub/ui/screens/projects_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final project = ProjectInfo(
    id: 'one',
    name: 'Summer campaign',
    year: '2026',
    month: 'JUNE',
    createdAt: '2026-06-01T00:00:00Z',
    lastOpenedAt: '2026-06-02T00:00:00Z',
    folderPath: 'Z:/missing/project',
  );

  testWidgets('shows the Electron-style sidebar and selected detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider.overrideWith((_) async => [project]),
        ],
        child: const MaterialApp(home: Scaffold(body: ProjectsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('projects-sidebar')), findsOneWidget);
    expect(find.text('Summer campaign'), findsNWidgets(2));
    expect(find.text('Project files'), findsOneWidget);
    expect(find.byTooltip('New project'), findsOneWidget);

    expect(find.byKey(const Key('projects-header-glass')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('sidebar-header'))).height, 68);
    expect(tester.getSize(find.byKey(const Key('project-header'))).height, 68);
  });

  testWidgets('new-project button opens an anchored glass popup', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider.overrideWith((_) async => <ProjectInfo>[]),
        ],
        child: const MaterialApp(home: Scaffold(body: ProjectsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New project'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('project-create-popover')), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(find.text('Create'), findsOneWidget);
    expect(find.byKey(const Key('project-name')), findsOneWidget);
    expect(find.byKey(const Key('project-url')), findsOneWidget);
  });
}
