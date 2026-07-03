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

  testWidgets('folders drill in, files open through callback, size formatted', (
    tester,
  ) async {
    FolderEntry? opened;
    final clip = FolderEntry(
      name: 'clip.mp4',
      path: r'D:\Videos\Project\FOOTAGE\clip.mp4',
      isFolder: false,
    );
    final folder = FolderEntry(
      name: 'FOOTAGE',
      path: r'D:\Videos\Project\FOOTAGE',
      isFolder: true,
      children: [clip],
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

    // Tapping a non-empty folder drills in (no Explorer), revealing its file.
    await tester.tap(find.text('FOOTAGE'));
    await tester.pumpAndSettle();
    expect(opened, isNull);
    expect(find.text('clip.mp4'), findsOneWidget);

    // Tapping the file opens it through the callback.
    await tester.tap(find.text('clip.mp4'));
    expect(opened, same(clip));
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
