import 'dart:convert';
import 'dart:io';

import 'package:edithub/data/services/auth_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  setUp(
    () => temp = Directory.systemTemp.createTempSync('edithub_icloud_auth_'),
  );
  tearDown(() => temp.deleteSync(recursive: true));

  test('creates the legacy auth file inside iCloud EditHub folder', () async {
    final storage = AuthStorageService.forICloud(temp.path);

    expect(await storage.load(), isNull);

    final file = File(p.join(temp.path, 'EditHub', 'auth.json'));
    expect(file.existsSync(), isTrue);
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(json['serverURL'], 'http://127.0.0.1:3000');
    expect(json['lastSync'], isA<String>());
    expect(json.containsKey('token'), isFalse);
  });

  test('restores a provisioned token from the legacy iCloud shape', () async {
    final file = File(p.join(temp.path, 'EditHub', 'auth.json'));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'serverURL': 'http://server.test:3000',
        'token': _jwt(),
        'userEmail': 'editor@example.com',
        'workspaceId': 'workspace-1',
        'lastSync': DateTime.now().toUtc().toIso8601String(),
      }),
    );

    final session = await AuthStorageService.forICloud(temp.path).load();

    expect(session?.userId, 'user-1');
    expect(session?.workspaceId, 'workspace-1');
    expect(session?.serverUrl, 'http://server.test:3000');
  });
}

String _jwt() {
  String part(Map<String, Object> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'exp': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000, 'userId': 'user-1', 'workspaceId': 'workspace-1'})}.signature';
}
