import 'dart:io';

import 'package:edithub/services/downloader_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes Google Drive folders without rewriting them as files', () {
    const url = 'https://drive.google.com/drive/folders/folder-id?usp=sharing';
    expect(normalizeDownloadUrl(url), url);
  });

  test('normalizes Google Drive and Dropbox share links', () {
    expect(
      normalizeDownloadUrl('https://drive.google.com/file/d/abc123/view'),
      'https://drive.google.com/uc?export=download&id=abc123',
    );
    expect(
      normalizeDownloadUrl('https://www.dropbox.com/s/abc/video.mp4?dl=0'),
      'https://dl.dropboxusercontent.com/s/abc/video.mp4?dl=1',
    );
    expect(
      () => normalizeDownloadUrl('not a URL'),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'downloads redirects, uses response filename, and reports progress',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <String>[];
      server.listen((request) async {
        requests.add(request.uri.path);
        if (request.uri.path == '/start') {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set('location', '/file');
        } else {
          request.response.headers
            ..contentLength = 6
            ..set('content-disposition', 'attachment; filename="clip.mp4"');
          request.response.add([1, 2, 3]);
          await request.response.flush();
          request.response.add([4, 5, 6]);
        }
        await request.response.close();
      });
      final temp = Directory.systemTemp.createTempSync('edithub_download_');
      final progress = <DownloadProgress>[];

      try {
        final files = await DownloaderService(maxAttempts: 1).downloadAll(
          projectId: 'project-1',
          urls: ['http://127.0.0.1:${server.port}/start'],
          destinationFolder: temp.path,
          onProgress: progress.add,
        );

        expect(requests, ['/start', '/file']);
        expect(files.single.path, endsWith('clip.mp4'));
        expect(await files.single.readAsBytes(), [1, 2, 3, 4, 5, 6]);
        expect(progress.last.percent, 100);
        expect(progress.last.bytesDownloaded, 6);
      } finally {
        await server.close(force: true);
        temp.deleteSync(recursive: true);
      }
    },
  );
}
