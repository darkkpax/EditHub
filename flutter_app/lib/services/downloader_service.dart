import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class DownloadProgress {
  const DownloadProgress({
    required this.projectId,
    required this.fileUrl,
    required this.fileName,
    required this.percent,
    required this.bytesDownloaded,
    required this.totalBytes,
  });

  final String projectId;
  final String fileUrl;
  final String fileName;
  final int percent;
  final int bytesDownloaded;
  final int totalBytes;
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();
}

String normalizeDownloadUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw FormatException('Некорректная ссылка: $rawUrl');
  }

  if (uri.host == 'drive.google.com') {
    final match = RegExp(r'/file/d/([^/]+)').firstMatch(uri.path);
    final id = match?.group(1) ?? uri.queryParameters['id'];
    if (id != null && id.isNotEmpty) {
      return Uri.https('drive.google.com', '/uc', {
        'export': 'download',
        'id': id,
      }).toString();
    }
  }

  if (uri.host == 'dropbox.com' || uri.host == 'www.dropbox.com') {
    return uri
        .replace(
          host: 'dl.dropboxusercontent.com',
          queryParameters: {...uri.queryParameters, 'dl': '1'},
        )
        .toString();
  }
  return uri.toString();
}

class DownloaderService {
  DownloaderService({
    http.Client? client,
    this.maxAttempts = 5,
    this.retryBaseDelay = const Duration(seconds: 2),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final int maxAttempts;
  final Duration retryBaseDelay;
  final Set<String> _cancelledProjects = {};

  void cancel(String projectId) => _cancelledProjects.add(projectId);

  Future<List<File>> downloadAll({
    required String projectId,
    required List<String> urls,
    required String destinationFolder,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    _cancelledProjects.remove(projectId);
    await Directory(destinationFolder).create(recursive: true);
    try {
      return await Future.wait(
        urls.map(
          (url) => _downloadOne(
            projectId: projectId,
            rawUrl: url,
            destinationFolder: destinationFolder,
            onProgress: onProgress,
          ),
        ),
      );
    } finally {
      _cancelledProjects.remove(projectId);
    }
  }

  Future<File> _downloadOne({
    required String projectId,
    required String rawUrl,
    required String destinationFolder,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final normalized = normalizeDownloadUrl(rawUrl);
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      _throwIfCancelled(projectId);
      try {
        final fallbackName = _filenameFromUri(Uri.parse(normalized));
        final partial = File(p.join(destinationFolder, '$fallbackName.part'));
        final existing = await partial.exists() ? await partial.length() : 0;
        final request = http.Request('GET', Uri.parse(normalized));
        if (existing > 0) {
          request.headers[HttpHeaders.rangeHeader] = 'bytes=$existing-';
        }
        final response = await _client
            .send(request)
            .timeout(const Duration(seconds: 30));

        if (response.statusCode != HttpStatus.ok &&
            response.statusCode != HttpStatus.partialContent) {
          final error = HttpException(
            'HTTP ${response.statusCode}',
            uri: Uri.parse(normalized),
          );
          if (!_retryable(response.statusCode)) {
            throw error;
          }
          lastError = error;
          await response.stream.drain<void>();
          throw error;
        }

        final responseName =
            _filenameFromHeaders(response.headers) ?? fallbackName;
        final safeName = _safeFilename(responseName);
        final finalFile = File(p.join(destinationFolder, safeName));
        final append =
            response.statusCode == HttpStatus.partialContent && existing > 0;
        final sink = partial.openWrite(
          mode: append ? FileMode.append : FileMode.write,
        );
        var downloaded = append ? existing : 0;
        final total = _totalBytes(response, downloaded);
        try {
          await for (final chunk in response.stream) {
            _throwIfCancelled(projectId);
            sink.add(chunk);
            downloaded += chunk.length;
            onProgress?.call(
              DownloadProgress(
                projectId: projectId,
                fileUrl: rawUrl,
                fileName: safeName,
                percent: total > 0
                    ? ((downloaded / total) * 100).round().clamp(0, 100)
                    : 0,
                bytesDownloaded: downloaded,
                totalBytes: total,
              ),
            );
          }
        } finally {
          await sink.close();
        }

        if (await finalFile.exists()) await finalFile.delete();
        await partial.rename(finalFile.path);
        onProgress?.call(
          DownloadProgress(
            projectId: projectId,
            fileUrl: rawUrl,
            fileName: safeName,
            percent: 100,
            bytesDownloaded: downloaded,
            totalBytes: total > 0 ? total : downloaded,
          ),
        );
        await _extractZip(finalFile, destinationFolder);
        return finalFile;
      } on DownloadCancelledException {
        rethrow;
      } catch (error) {
        lastError = error;
        if (attempt == maxAttempts) break;
        final multiplier = attempt.clamp(1, 10);
        await Future<void>.delayed(retryBaseDelay * multiplier);
      }
    }
    throw Exception('Не удалось скачать файл: $lastError');
  }

  void _throwIfCancelled(String projectId) {
    if (_cancelledProjects.contains(projectId)) {
      throw const DownloadCancelledException();
    }
  }

  bool _retryable(int status) =>
      status == 408 || status == 425 || status == 429 || status >= 500;

  int _totalBytes(http.StreamedResponse response, int existing) {
    final range = response.headers[HttpHeaders.contentRangeHeader];
    final rangeTotal = range == null
        ? null
        : int.tryParse(RegExp(r'/([0-9]+)$').firstMatch(range)?.group(1) ?? '');
    return rangeTotal ?? ((response.contentLength ?? 0) + existing);
  }

  String _filenameFromUri(Uri uri) {
    final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final decoded = Uri.decodeComponent(name);
    return decoded.contains('.')
        ? _safeFilename(decoded)
        : 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

  String? _filenameFromHeaders(Map<String, String> headers) {
    final disposition = headers['content-disposition'];
    if (disposition == null) return null;
    final utf8Name = RegExp(
      "filename\\*=UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(disposition)?.group(1);
    if (utf8Name != null) return Uri.decodeComponent(utf8Name);
    return RegExp(
      'filename="?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(disposition)?.group(1)?.trim();
  }

  String _safeFilename(String value) {
    final cleaned = p
        .basename(value)
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    return cleaned.isEmpty
        ? 'download_${DateTime.now().millisecondsSinceEpoch}'
        : cleaned;
  }

  Future<void> _extractZip(File file, String destinationFolder) async {
    if (p.extension(file.path).toLowerCase() != '.zip') return;
    try {
      await extractFileToDisk(file.path, destinationFolder);
      await file.delete();
    } catch (_) {
      // Keep the ZIP when extraction fails so the download is not lost.
    }
  }
}
