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
    // Modern Dropbox shared *folder* (/scl/fo/) must stay on www.dropbox.com:
    // Dropbox answers 404 when a folder link is served from the content host.
    // Only single files may be rewritten to dl.dropboxusercontent.com.
    final modernResult = normalizeDownloadUrl(
      'https://www.dropbox.com/scl/fo/j37idqx0q0bu8qzaxd8kb/abc?rlkey=xyz&dl=0',
    );
    expect(modernResult, contains('www.dropbox.com'));
    expect(modernResult, isNot(contains('dl.dropboxusercontent.com')));
    expect(modernResult, contains('scl/fo/'));
    expect(modernResult, contains('rlkey=xyz'));
    expect(modernResult, contains('dl=1'));

    // A legacy shared folder (/sh/) gets the same treatment.
    final legacyFolder = normalizeDownloadUrl(
      'https://www.dropbox.com/sh/abc123/AAA?dl=0',
    );
    expect(legacyFolder, contains('www.dropbox.com'));
    expect(legacyFolder, isNot(contains('dl.dropboxusercontent.com')));

    // A modern single *file* (/scl/fi/) still uses the content host.
    final modernFile = normalizeDownloadUrl(
      'https://www.dropbox.com/scl/fi/abc/clip.mov?rlkey=xyz&dl=0',
    );
    expect(modernFile, contains('dl.dropboxusercontent.com'));
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

  test('does not retry a permanent HTTP status', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var hits = 0;
    server.listen((request) async {
      hits++;
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    final temp = Directory.systemTemp.createTempSync('edithub_404_');

    try {
      // maxAttempts is 5, but a 404 will never become valid — the download must
      // give up after a single request instead of burning every attempt.
      await expectLater(
        DownloaderService(
          maxAttempts: 5,
          retryBaseDelay: Duration.zero,
        ).downloadAll(
          projectId: 'project-404',
          urls: ['http://127.0.0.1:${server.port}/missing'],
          destinationFolder: temp.path,
        ),
        throwsA(isA<HttpException>()),
      );
      expect(hits, 1);
    } finally {
      await server.close(force: true);
      temp.deleteSync(recursive: true);
    }
  });

  test('retries a transient HTTP status', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var hits = 0;
    server.listen((request) async {
      hits++;
      if (hits < 3) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
      } else {
        request.response.headers
          ..contentLength = 3
          ..set('content-disposition', 'attachment; filename="ok.bin"');
        request.response.add([7, 8, 9]);
      }
      await request.response.close();
    });
    final temp = Directory.systemTemp.createTempSync('edithub_503_');

    try {
      final files = await DownloaderService(
        maxAttempts: 5,
        retryBaseDelay: Duration.zero,
      ).downloadAll(
        projectId: 'project-503',
        urls: ['http://127.0.0.1:${server.port}/flaky'],
        destinationFolder: temp.path,
      );
      expect(hits, 3);
      expect(await files.single.readAsBytes(), [7, 8, 9]);
    } finally {
      await server.close(force: true);
      temp.deleteSync(recursive: true);
    }
  });
}
