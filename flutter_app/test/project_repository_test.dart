import 'dart:io';
import 'dart:convert';

import 'package:edithub/data/repositories/project_repository.dart';
import 'package:edithub/data/services/project_api_service.dart';
import 'package:edithub/domain/models/auth_session.dart';
import 'package:edithub/models/models.dart';
import 'package:edithub/services/downloader_service.dart';
import 'package:edithub/services/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('edithub_project_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('create writes the complete folder structure and manifest', () async {
    final store = ProjectStore();
    final repository = ProjectRepository(
      store: store,
      downloader: DownloaderService(maxAttempts: 1),
    );

    final project = await repository.create(
      projectsFolder: temp.path,
      name: 'Client film',
      urls: const [],
    );

    expect(project.status, ProjectStatus.ready);
    expect(
      File(p.join(project.folderPath!, kProjectManifest)).existsSync(),
      isTrue,
    );
    for (final folder in kDefaultProjectFolders) {
      expect(
        Directory(
          p.join(project.folderPath!, folder.replaceAll('/', p.separator)),
        ).existsSync(),
        isTrue,
        reason: folder,
      );
    }
  });

  test('create downloads footage and persists final ready state', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers
        ..contentLength = 3
        ..set('content-disposition', 'attachment; filename="source.mov"');
      request.response.add([1, 2, 3]);
      await request.response.close();
    });
    final store = ProjectStore();
    final repository = ProjectRepository(
      store: store,
      downloader: DownloaderService(maxAttempts: 1),
    );

    try {
      final project = await repository.create(
        projectsFolder: temp.path,
        name: 'Download film',
        urls: ['http://127.0.0.1:${server.port}/source'],
      );
      expect(project.status, ProjectStatus.downloading);

      await repository.waitForDownload(project.id);

      final saved = store.readProjectInfo(project.folderPath!);
      expect(saved?.status, ProjectStatus.ready);
      expect(
        File(p.join(project.folderPath!, 'FOOTAGE', 'source.mov')).existsSync(),
        isTrue,
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('create rejects names that can escape the projects root', () async {
    final repository = ProjectRepository(
      store: ProjectStore(),
      downloader: DownloaderService(maxAttempts: 1),
    );

    expect(
      () => repository.create(
        projectsFolder: temp.path,
        name: '../outside',
        urls: const [],
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('authenticated create posts metadata to the catalog API', () async {
    late Map<String, dynamic> body;
    final repository = ProjectRepository(
      store: ProjectStore(),
      downloader: DownloaderService(maxAttempts: 1),
      api: ProjectApiService(
        client: MockClient((request) async {
          expect(request.url.toString(), 'http://server.test/projects');
          expect(request.headers['authorization'], 'Bearer token');
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(request.body, 201);
        }),
      ),
    );

    await repository.create(
      projectsFolder: temp.path,
      name: 'Shared project',
      urls: const ['https://example.com/footage.mp4'],
      session: const AuthSession(
        token: 'token',
        userId: 'user',
        workspaceId: 'workspace',
        email: 'editor@example.com',
        serverUrl: 'http://server.test',
      ),
      startDownloads: false,
    );

    expect(body['name'], 'Shared project');
    expect(body['footageLinks'], ['https://example.com/footage.mp4']);
  });
}
