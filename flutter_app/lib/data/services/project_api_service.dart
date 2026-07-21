import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/auth_session.dart';
import '../../models/models.dart';

class ProjectApiException implements Exception {
  const ProjectApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ProjectApiService {
  ProjectApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> createProject(AuthSession session, ProjectInfo project) async {
    final uri = Uri.parse('${session.serverUrl}/projects');
    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        'Authorization': 'Bearer ${session.token}',
      },
      body: jsonEncode({
        'id': project.id,
        'name': project.name,
        'year': project.year,
        'month': project.month,
        'footageLinks': project.footageUrls,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Server returned HTTP ${response.statusCode}.';
      try {
        message =
            (jsonDecode(response.body) as Map<String, dynamic>)['error']
                ?.toString() ??
            message;
      } catch (_) {}
      throw ProjectApiException(message, response.statusCode);
    }
  }
}
