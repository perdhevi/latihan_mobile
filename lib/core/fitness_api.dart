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

/// A decoded success body plus the `ETag` the server sent with it, which a
/// later `PUT` returns as `If-Match`.
class ApiResponse {
  final Map<String, dynamic> body;
  final String? etag;
  ApiResponse(this.body, this.etag);
}

/// Holds the session's tokens in memory. The access token is short-lived and
/// never leaves memory; the refresh token can be handed to storage through
/// [onRefreshToken] (called with null when the session ends) and given back as
/// [refreshToken] to resume without a password.
class FitnessApi {
  final Uri base;
  final http.Client _client;
  final void Function(String? refreshToken)? onRefreshToken;
  String? _access;
  String? _refresh;
  Future<void>? _refreshing;

  FitnessApi(
    String url, {
    http.Client? client,
    String? refreshToken,
    this.onRefreshToken,
  }) : _refresh = refreshToken,
       base = Uri.parse(url.endsWith('/') ? url : '$url/'),
       _client = client ?? http.Client() {
    if (!['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw ArgumentError('Enter a valid API URL.');
    }
  }

  /// True while there is a session, including one resumed from a stored
  /// refresh token whose access token has not been fetched yet.
  bool get signedIn => _access != null || _refresh != null;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async => (await _send(
    method,
    path,
    body: body,
    authenticated: authenticated,
  )).body;

  Future<ApiResponse> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool authenticated = true,
    bool retry = true,
  }) async {
    final request = http.Request(method, base.resolve(path));
    request.headers['Content-Type'] = 'application/json';
    if (headers != null) request.headers.addAll(headers);
    if (authenticated) {
      if (_access == null && _refresh != null) await _refreshSession();
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
      await _refreshSession();
      return _send(method, path, body: body, headers: headers, retry: false);
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
    return ApiResponse(
      Map<String, dynamic>.from(decoded as Map),
      response.headers['etag'],
    );
  }

  /// Trades the refresh token for new tokens. Concurrent callers share one
  /// request, since the server rotates the refresh token on use.
  Future<void> _refreshSession() => _refreshing ??= (() async {
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
      // A rejected refresh token ends the session; a network error does not.
      if (e.status == 401) _forget();
      rethrow;
    }
  })().whenComplete(() => _refreshing = null);

  void _tokens(Map<String, dynamic> data) {
    final access = data['access_token'] as String;
    final refresh = data['refresh_token'] as String;
    _access = access;
    _refresh = refresh;
    onRefreshToken?.call(refresh);
  }

  void _forget() {
    _access = null;
    _refresh = null;
    onRefreshToken?.call(null);
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

  // Generic resource calls used by synchronization. Paths are relative to the
  // API base, e.g. `plans/<id>`.

  Future<ApiResponse> get(String path) => _send('GET', path);

  /// [idempotencyKey] makes a retried create return the original record
  /// instead of making a duplicate.
  Future<ApiResponse> post(
    String path,
    Map<String, dynamic> body, {
    String? idempotencyKey,
  }) => _send(
    'POST',
    path,
    body: body,
    headers: {'Idempotency-Key': ?idempotencyKey},
  );

  /// Replaces the record. [ifMatch] is the `ETag` from the read the change is
  /// based on; the server answers 412 if the record has changed since.
  Future<ApiResponse> put(
    String path,
    Map<String, dynamic> body, {
    String? ifMatch,
  }) => _send('PUT', path, body: body, headers: {'If-Match': ?ifMatch});

  Future<void> delete(String path) => _send('DELETE', path);

  /// Every item of a paginated collection.
  Future<List<Map<String, dynamic>>> listAll(String path) async {
    final items = <Map<String, dynamic>>[];
    String? cursor;
    do {
      final query = Uri(queryParameters: {'limit': '100', 'cursor': ?cursor});
      final page = (await _send('GET', '$path?${query.query}')).body;
      items.addAll([
        for (final item in page['items'] as List)
          Map<String, dynamic>.from(item as Map),
      ]);
      cursor = page['next_cursor'] as String?;
    } while (cursor != null);
    return items;
  }

  Future<void> signOut() async {
    final refresh = _refresh;
    _forget();
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
