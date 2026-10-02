import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  ApiException(this.status, this.code, this.message);
  @override
  String toString() => message;
}

/// Credentials are held in memory only; local fitness data is independent.
class FitnessApi {
  final Uri base;
  final http.Client _client;
  String? _access;
  String? _refresh;

  FitnessApi(String url, {http.Client? client})
    : base = Uri.parse(url.endsWith('/') ? url : '$url/'),
      _client = client ?? http.Client() {
    if (!['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw ArgumentError('Enter a valid API URL.');
    }
  }

  bool get signedIn => _access != null;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    bool retry = true,
  }) async {
    final request = http.Request(method, base.resolve(path));
    request.headers['Content-Type'] = 'application/json';
    if (authenticated) {
      if (_access == null) {
        throw ApiException(401, 'unauthenticated', 'Sign in to continue.');
      }
      request.headers['Authorization'] = 'Bearer $_access';
    }
    if (body != null) request.body = jsonEncode(body);
    final response = await (() async {
      return http.Response.fromStream(await _client.send(request));
    })().timeout(const Duration(seconds: 20));
    if (response.statusCode == 401 &&
        authenticated &&
        retry &&
        _refresh != null) {
      try {
        _tokens(
          await _request(
            'POST',
            'auth/refresh',
            body: {'refresh_token': _refresh},
            authenticated: false,
          ),
        );
      } on ApiException catch (e) {
        if (e.status == 401) {
          _access = null;
          _refresh = null;
        }
        rethrow;
      }
      return _request(method, path, body: body, retry: false);
    }
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded is Map ? decoded['error'] : null;
      throw ApiException(
        response.statusCode,
        error is Map ? error['code'] as String? ?? 'api_error' : 'api_error',
        error is Map
            ? error['message'] as String? ?? 'Server request failed.'
            : 'Server request failed.',
      );
    }
    return Map<String, dynamic>.from(decoded as Map);
  }

  void _tokens(Map<String, dynamic> data) {
    final access = data['access_token'] as String;
    final refresh = data['refresh_token'] as String;
    _access = access;
    _refresh = refresh;
  }

  Future<void> signIn(
    String email,
    String password, {
    bool register = false,
  }) async {
    _tokens(
      await _request(
        'POST',
        register ? 'auth/register' : 'auth/login',
        body: {'email': email.trim(), 'password': password},
        authenticated: false,
      ),
    );
  }

  Future<Map<String, dynamic>> profile() => _request('GET', 'users/me');
  Future<Map<String, dynamic>> createProfile(String name) =>
      _request('POST', 'users', body: {'display_name': name.trim()});
  Future<Map<String, dynamic>> sessions({String? cursor}) => _request(
    'GET',
    'sessions?${Uri(queryParameters: {'limit': '20', 'cursor': ?cursor}).query}',
  );

  Future<void> signOut() async {
    final refresh = _refresh;
    _access = null;
    _refresh = null;
    if (refresh != null) {
      await _request(
        'POST',
        'auth/logout',
        body: {'refresh_token': refresh},
        authenticated: false,
      );
    }
  }

  void close() => _client.close();
}
