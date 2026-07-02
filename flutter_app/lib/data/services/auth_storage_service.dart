import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/auth_session.dart';

class AuthStorageService {
  AuthStorageService([File? file]) : _file = file ?? File(_fallbackPath);

  AuthStorageService.forICloud(String icloudPath)
    : _file = File(p.join(icloudPath, 'EditHub', 'auth.json'));

  final File _file;

  static String get _fallbackPath {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return p.join(home, '.edithub', 'auth.json');
  }

  Future<AuthSession?> load() async {
    try {
      if (!await _file.exists()) {
        await _writeDefault();
        return null;
      }
      final json =
          jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      final token = json['token']?.toString();
      if (token == null || token.isEmpty) return null;
      final payload = _jwtPayload(token);
      final session = AuthSession(
        token: token,
        userId:
            json['userId']?.toString() ?? payload?['userId']?.toString() ?? '',
        workspaceId:
            json['workspaceId']?.toString() ??
            payload?['workspaceId']?.toString() ??
            '',
        email: json['userEmail']?.toString() ?? json['email']?.toString() ?? '',
        serverUrl:
            json['serverURL']?.toString() ??
            json['serverUrl']?.toString() ??
            'http://127.0.0.1:3000',
      );
      if (session.isExpired) return null;
      return session;
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> save(AuthSession session) => saveRaw({
    'serverURL': session.serverUrl,
    'token': session.token,
    if (session.email.isNotEmpty) 'userEmail': session.email,
    if (session.workspaceId.isNotEmpty) 'workspaceId': session.workspaceId,
    'lastSync': DateTime.now().toUtc().toIso8601String(),
  });

  Future<void> saveRaw(Map<String, dynamic> json) async {
    await _file.parent.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
    );
    if (await _file.exists()) await _file.delete();
    await temporary.rename(_file.path);
  }

  Future<void> clear() async {
    await _writeDefault();
  }

  Future<void> _writeDefault() => saveRaw({
    'serverURL': 'http://127.0.0.1:3000',
    'lastSync': DateTime.now().toUtc().toIso8601String(),
  });

  Map<String, dynamic>? _jwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      return jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
          )
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
