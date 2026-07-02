import 'package:edithub/models/models.dart';
import 'package:edithub/ui/design/motion.dart';
import 'package:edithub/ui/widgets/project_detail.dart';
import 'package:edithub/ui/widgets/project_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final project = ProjectInfo(
    id: 'project',
    name: 'Project',
    year: '2026',
    month: 'JUNE',
    createdAt: '2026-06-01T00:00:00Z',
    lastOpenedAt: '2026-06-01T00:00:00Z',
    folderPath: r'D:\Videos\Project',
    sizeBytes: 1536,
  );

  testWidgets('folder rows open through callback and size is formatted', (
    tester,
  ) async {
    FolderEntry? opened;
    final folder = FolderEntry(
      name: 'FOOTAGE',
      path: r'D:\Videos\Project\FOOTAGE',
      isFolder: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectDetail(
            project: project,
            folders: Future.value([folder]),
            size: Future.value(1536),
            onEntryOpen: (entry) => opened = entry,
            onOpen: () {},
            onReveal: () {},
            onArchive: () {},
            onRestore: () {},
            onDelete: () {},
            onCancelDownload: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1.5 KB'), findsOneWidget);
    expect(find.byKey(const Key('project-open-action')), findsOneWidget);
    expect(find.byKey(const Key('project-reveal-action')), findsOneWidget);
    expect(find.byKey(const Key('project-archive-action')), findsOneWidget);
    expect(find.byKey(const Key('project-delete-action')), findsOneWidget);
    await tester.tap(find.text('FOOTAGE'));
    expect(opened, same(folder));
  });

  testWidgets('sidebar pins a blurred search header and animates rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectSidebar(
            projects: [project],
            selectedId: project.id,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(FadeInUp), findsWidgets);
  });
}
