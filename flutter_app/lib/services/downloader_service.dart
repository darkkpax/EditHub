import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'google_drive_auth_service.dart';

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

/// Wraps an HTTP failure that retrying cannot fix (404, 403, 401…), so the
/// retry loop can tell it apart from a transient error and stop immediately.
class _PermanentHttpException implements Exception {
  const _PermanentHttpException(this.inner);
  final Object inner;
}

String normalizeDownloadUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw FormatException('Invalid link: $rawUrl');
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

  if (uri.host == 'dropbox.com' ||
      uri.host == 'www.dropbox.com' ||
      uri.host == 'dl.dropboxusercontent.com') {
    // Dropbox changed from /s/ to /scl/fo/ and /sh/ for new shared links.
    // Both formats need dl=1, and the modern format needs rlkey to persist.
    final params = {...uri.queryParameters, 'dl': '1'};

    // A shared *folder* must keep the www host: Dropbox answers 404 when a
    // /scl/fo (or legacy /sh) link is served from dl.dropboxusercontent.com.
    // The supported flow is www + dl=1, which redirects to a short-lived
    // zip_download_get URL. Only single *files* may use the content host.
    if (isDropboxFolderLink(uri)) {
      return uri
          .replace(host: 'www.dropbox.com', queryParameters: params)
          .toString();
    }

    return uri
        .replace(
          host: 'dl.dropboxusercontent.com',
          queryParameters: params,
        )
        .toString();
  }
  return uri.toString();
}

/// Whether a Dropbox URL points at a shared folder rather than a single file.
bool isDropboxFolderLink(Uri uri) {
  final path = uri.path.toLowerCase();
  return path.contains('/scl/fo/') || path.startsWith('/sh/');
}

class DownloaderService {
  DownloaderService({
    http.Client? client,
    this.maxAttempts = 5,
    this.retryBaseDelay = const Duration(seconds: 2),
    this.maxConcurrent = 4,
    this.stallTimeout = const Duration(seconds: 90),
    this.googleDriveAuth,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final int maxAttempts;
  final Duration retryBaseDelay;

  /// How long the body stream may deliver zero bytes before the attempt is
  /// treated as stalled and retried.
  final Duration stallTimeout;

  /// Cap on files downloading at once so a many-file project doesn't open
  /// dozens of sockets and starve the disk/network.
  final int maxConcurrent;
  final GoogleDriveAuthService? googleDriveAuth;

  /// Run counter per project. `downloadAll` claims a run id at entry and only
  /// that run reacts to a cancel — so a cancel meant for a finished run cannot
  /// leak into the next one, and two concurrent runs for the same project
  /// cancel independently. (Previously a shared `Set<String>` was cleared in a
  /// `finally`, which dropped a cancel that arrived while a run was ending.)
  int _runCounter = 0;
  final Map<String, int> _activeRuns = {};
  final Set<int> _cancelledRuns = {};

  /// Cancel the download run currently in flight for [projectId], if any.
  void cancel(String projectId) {
    final runId = _activeRuns[projectId];
    if (runId != null) _cancelledRuns.add(runId);
  }

  Future<List<File>> downloadAll({
    required String projectId,
    required List<String> urls,
    required String destinationFolder,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final runId = ++_runCounter;
    _activeRuns[projectId] = runId;
    await Directory(destinationFolder).create(recursive: true);
    try {
      final jobs = <({String rawUrl, String? driveId, String? relativePath})>[];
      for (final url in urls) {
        if (Uri.parse(url).host == 'drive.google.com' &&
            googleDriveAuth != null) {
          final files = await googleDriveAuth!.filesFor(url);
          if (files.isNotEmpty) {
            jobs.addAll(
              files.map(
                (file) =>
                    (rawUrl: url, driveId: file.id, relativePath: file.path),
              ),
            );
            continue;
          }
        }
        jobs.add((rawUrl: url, driveId: null, relativePath: null));
      }
      // Bounded worker pool: at most [maxConcurrent] files in flight. Workers
      // pull the next job index until the queue drains.
      final results = List<File?>.filled(jobs.length, null);
      var next = 0;
      Future<void> worker() async {
        while (true) {
          final index = next++;
          if (index >= jobs.length) break;
          final job = jobs[index];
          results[index] = await _downloadOne(
            projectId: projectId,
            runId: runId,
            rawUrl: job.rawUrl,
            normalizedUrl: job.driveId == null
                ? null
                : 'https://www.googleapis.com/drive/v3/files/${job.driveId}?alt=media',
            destinationFolder: job.relativePath == null
                ? destinationFolder
                : p.join(destinationFolder, p.dirname(job.relativePath!)),
            preferredName: job.relativePath == null
                ? null
                : p.basename(job.relativePath!),
            onProgress: onProgress,
          );
        }
      }

      await Future.wait([
        for (var i = 0; i < min(maxConcurrent, jobs.length); i++) worker(),
      ]);
      return results.whereType<File>().toList();
    } finally {
      // Retire this run. A cancel that arrives later targets whatever run is
      // active then — not this finished one.
      if (_activeRuns[projectId] == runId) _activeRuns.remove(projectId);
      _cancelledRuns.remove(runId);
    }
  }

  Future<File> _downloadOne({
    required String projectId,
    required int runId,
    required String rawUrl,
    required String destinationFolder,
    String? normalizedUrl,
    String? preferredName,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final normalized = normalizedUrl ?? normalizeDownloadUrl(rawUrl);
    await Directory(destinationFolder).create(recursive: true);
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      _throwIfCancelled(runId);
      try {
        final fallbackName =
            preferredName ?? _filenameFromUri(Uri.parse(normalized));
        final partial = File(p.join(destinationFolder, '$fallbackName.part'));
        final existing = await partial.exists() ? await partial.length() : 0;
        final request = http.Request('GET', Uri.parse(normalized));
        // ponytail: Dropbox blocks requests without User-Agent. Set a generic one
        // to avoid 403 Forbidden responses on newer shared links (/scl/fo/, /sh/).
        request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
        if (Uri.parse(rawUrl).host == 'drive.google.com') {
          final token = await googleDriveAuth?.accessToken();
          if (token != null) {
            request.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
          }
        }
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
          await response.stream.drain<void>();
          lastError = error;
          // A permanent status (404, 403, 401…) will not become valid by asking
          // again. Wrap it so the catch-all below re-throws immediately instead
          // of burning every remaining attempt — the previous `throw error`
          // landed in that same catch and was retried like any other failure.
          if (!_retryable(response.statusCode)) {
            throw _PermanentHttpException(error);
          }
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
          // The `.timeout` above only bounds the response *headers*. Once the
          // stream is open a stalled connection can deliver nothing forever
          // (a VPN toggling, Wi-Fi roaming) and the download hangs silently.
          // Bound the gap between chunks so the retry loop can reconnect —
          // the .part file on disk means it resumes rather than restarts.
          final stream = response.stream.timeout(
            stallTimeout,
            // Named `eventSink` to avoid shadowing the file `sink` above.
            onTimeout: (eventSink) => eventSink.addError(
              TimeoutException('No data for ${stallTimeout.inSeconds}s'),
            ),
          );
          await for (final chunk in stream) {
            _throwIfCancelled(runId);
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
      } on _PermanentHttpException catch (permanent) {
        // Not worth another attempt — surface the underlying HTTP error as-is.
        throw permanent.inner;
      } catch (error) {
        lastError = error;
        if (attempt == maxAttempts) break;
        final multiplier = attempt.clamp(1, 10);
        await Future<void>.delayed(retryBaseDelay * multiplier);
      }
    }
    throw Exception('Could not download file: $lastError');
  }

  void _throwIfCancelled(int runId) {
    if (_cancelledRuns.contains(runId)) {
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
