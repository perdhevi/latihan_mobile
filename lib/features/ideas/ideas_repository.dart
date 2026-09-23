import 'dart:convert';

import 'package:http/http.dart' as http;

class ExerciseIdea {
  final String name, category, tips;
  final Uri? video;
  ExerciseIdea({
    required this.name,
    required this.category,
    required this.tips,
    this.video,
  });
  factory ExerciseIdea.fromJson(Map<String, dynamic> data) {
    final raw = data['video_url'] as String?;
    final uri = raw == null ? null : Uri.tryParse(raw);
    return ExerciseIdea(
      name: data['name'] as String,
      category: data['category'] as String? ?? 'Training',
      tips: data['tips'] as String? ?? data['description'] as String? ?? '',
      video:
          uri != null &&
              (uri.scheme == 'https' || uri.scheme == 'http') &&
              uri.host.isNotEmpty
          ? uri
          : null,
    );
  }
}

class IdeasRepository {
  static const endpoint = String.fromEnvironment('EXERCISE_IDEAS_URL');
  final http.Client? client;
  final String url;
  IdeasRepository({this.client, this.url = endpoint});
  Future<List<ExerciseIdea>> load() async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        !['https', 'http'].contains(uri.scheme)) {
      throw StateError('Exercise ideas server is not configured.');
    }
    final transport = client ?? http.Client();
    try {
      final response = await transport
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw StateError('Server unavailable');
      final decoded = jsonDecode(response.body);
      final items = decoded is List
          ? decoded
          : (decoded as Map<String, dynamic>)['items'] as List;
      return items
          .map((item) => ExerciseIdea.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } finally {
      if (client == null) transport.close();
    }
  }
}
