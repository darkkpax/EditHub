import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class GoogleDriveAuthService {
  static String get credentialsPath => p.join(
    Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']!,
    '.edithub',
    'google-drive.json',
  );

  Map<String, dynamic> _read() {
    final file = File(credentialsPath);
    return file.existsSync()
        ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
        : <String, dynamic>{};
  }

  void _write(Map<String, dynamic> value) {
    final file = File(credentialsPath)..parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(value));
  }

  bool get isConfigured => (_read()['clientId'] as String? ?? '').isNotEmpty;
  bool get isSignedIn => (_read()['refreshToken'] as String? ?? '').isNotEmpty;

  Future<void> signIn() async {
    final credentials = _read();
    final clientId = credentials['clientId'] as String? ?? '';
    if (clientId.isEmpty) {
      throw Exception('Google client ID is not configured.');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}/oauth2callback';
    final verifier = base64Url
        .encode(List.generate(48, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
    final challenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    final state = base64Url
        .encode(List.generate(24, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
    final auth = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': 'https://www.googleapis.com/auth/drive.readonly',
      'access_type': 'offline',
      'prompt': 'consent',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
    });
    await Process.start('explorer.exe', [
      auth.toString(),
    ], mode: ProcessStartMode.detached);
    final request = await server.first.timeout(const Duration(minutes: 3));
    final code = request.uri.queryParameters['code'];
    final returnedState = request.uri.queryParameters['state'];
    request.response
      ..headers.contentType = ContentType.html
      ..write(
        '<h2>EditHub connected to Google Drive. You can close this tab.</h2>',
      );
    await request.response.close();
    await server.close(force: true);
    if (code == null || returnedState != state) {
      throw Exception('Google sign-in was cancelled or invalid.');
    }
    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': clientId,
        if ((credentials['clientSecret'] as String? ?? '').isNotEmpty)
          'client_secret': credentials['clientSecret'] as String,
        'code': code,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirect,
      },
    );
    if (response.statusCode ~/ 100 != 2) {
      throw Exception('Google token error ${response.statusCode}.');
    }
    final token = jsonDecode(response.body) as Map<String, dynamic>;
    _write({
      ...credentials,
      ...token,
      'expiresAt':
          DateTime.now().millisecondsSinceEpoch +
          ((token['expires_in'] as num).toInt() * 1000),
    });
  }

  Future<String?> accessToken() async {
    var credentials = _read();
    final current = credentials['access_token'] as String?;
    final expiresAt = (credentials['expiresAt'] as num?)?.toInt() ?? 0;
    if (current != null &&
        expiresAt > DateTime.now().millisecondsSinceEpoch + 60000) {
      return current;
    }
    final refresh =
        credentials['refresh_token'] as String? ??
        credentials['refreshToken'] as String?;
    if (refresh == null) return null;
    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': credentials['clientId'] as String,
        if ((credentials['clientSecret'] as String? ?? '').isNotEmpty)
          'client_secret': credentials['clientSecret'] as String,
        'refresh_token': refresh,
        'grant_type': 'refresh_token',
      },
    );
    if (response.statusCode ~/ 100 != 2) {
      throw Exception('Google session expired. Sign in again.');
    }
    final token = jsonDecode(response.body) as Map<String, dynamic>;
    credentials = {
      ...credentials,
      ...token,
      'refreshToken': refresh,
      'expiresAt':
          DateTime.now().millisecondsSinceEpoch +
          ((token['expires_in'] as num).toInt() * 1000),
    };
    _write(credentials);
    return token['access_token'] as String;
  }

  Future<List<GoogleDriveFile>> filesFor(String rawUrl) async {
    final uri = Uri.parse(rawUrl);
    final match = RegExp(r'/(?:folders|file/d)/([^/]+)').firstMatch(uri.path);
    final id = match?.group(1) ?? uri.queryParameters['id'];
    if (id == null) return const [];
    final token = await accessToken();
    final credentials = _read();
    final key = credentials['apiKey'] as String? ?? '';
    Future<Map<String, dynamic>> get(Uri url) async {
      final response = await http.get(
        url,
        headers: {
          if (token != null) HttpHeaders.authorizationHeader: 'Bearer $token',
        },
      );
      if (response.statusCode ~/ 100 != 2) {
        throw Exception(
          'Google Drive error ${response.statusCode}. Connect the account in Settings.',
        );
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    Uri api(String path, Map<String, String> query) => Uri.https(
      'www.googleapis.com',
      '/drive/v3/$path',
      {...query, if (key.isNotEmpty) 'key': key, 'supportsAllDrives': 'true'},
    );
    final root = await get(api('files/$id', {'fields': 'id,name,mimeType'}));
    if (root['mimeType'] != 'application/vnd.google-apps.folder') {
      return [GoogleDriveFile(id: id, path: root['name'] as String)];
    }
    final result = <GoogleDriveFile>[];
    Future<void> walk(String folderId, String prefix) async {
      String? pageToken;
      do {
        final page = await get(
          api('files', {
            'q': "'$folderId' in parents and trashed=false",
            'fields': 'nextPageToken,files(id,name,mimeType)',
            'pageSize': '1000',
          'pageToken': ?pageToken,
          }),
        );
        for (final item in page['files'] as List<dynamic>) {
          final file = item as Map<String, dynamic>;
          final path = p.join(prefix, file['name'] as String);
          if (file['mimeType'] == 'application/vnd.google-apps.folder') {
            await walk(file['id'] as String, path);
          } else if (!(file['mimeType'] as String).startsWith(
            'application/vnd.google-apps.',
          )) {
            result.add(GoogleDriveFile(id: file['id'] as String, path: path));
          }
        }
        pageToken = page['nextPageToken'] as String?;
      } while (pageToken != null);
    }

    await walk(id, root['name'] as String);
    return result;
  }
}

class GoogleDriveFile {
  const GoogleDriveFile({required this.id, required this.path});
  final String id;
  final String path;
}
