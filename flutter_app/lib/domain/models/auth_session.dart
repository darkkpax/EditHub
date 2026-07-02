import 'dart:convert';

class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.workspaceId,
    required this.email,
    required this.serverUrl,
  });

  final String token;
  final String userId;
  final String workspaceId;
  final String email;
  final String serverUrl;

  bool get isExpired {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;
      final exp = (payload['exp'] as num?)?.toInt();
      return exp == null || DateTime.now().millisecondsSinceEpoch >= exp * 1000;
    } catch (_) {
      return true;
    }
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    token: json['token'] as String,
    userId: json['userId'] as String,
    workspaceId: json['workspaceId'] as String,
    email: json['email'] as String,
    serverUrl: json['serverUrl'] as String,
  );

  Map<String, dynamic> toJson() => {
    'token': token,
    'userId': userId,
    'workspaceId': workspaceId,
    'email': email,
    'serverUrl': serverUrl,
  };
}
