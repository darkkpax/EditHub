import 'package:edithub/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ProjectStatus parses manifest values', () {
    expect(ProjectStatus.fromString('active'), ProjectStatus.active);
    expect(ProjectStatus.fromString('archive'), ProjectStatus.archive);
    expect(ProjectStatus.fromString(null), ProjectStatus.ready);
  });

  test('ProjectInfo round-trips through manifest JSON', () {
    final info = ProjectInfo(
      id: 'abc',
      name: 'Test',
      year: '2026',
      month: 'JUNE',
      createdAt: '2026-06-01T00:00:00Z',
      lastOpenedAt: '2026-06-02T00:00:00Z',
      status: ProjectStatus.ready,
    );
    final parsed = ProjectInfo.fromJson(
      Map<String, dynamic>.from(info.toManifestJson()),
    );
    expect(parsed.id, 'abc');
    expect(parsed.name, 'Test');
    expect(parsed.year, '2026');
    expect(parsed.status, ProjectStatus.ready);
  });
}
