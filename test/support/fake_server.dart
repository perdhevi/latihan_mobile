import 'dart:convert';

import 'package:http/http.dart' as http;

/// Behaves like the Go API as observed against a running server: IDs are
/// issued by the server and rejected from clients, PUT replaces and 404s on
/// unknown IDs, `Idempotency-Key` replays creates, `If-Match` guards PUT, a
/// session's `plan_exercise_id` must belong to its plan, and a plan in use
/// cannot be deleted.
class FakeServer {
  final plans = <String, Map<String, dynamic>>{};
  final sessions = <String, Map<String, dynamic>>{};
  final measurements = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? profile;
  final String userId;
  FakeServer({this.userId = 'user-1'});

  final _replays = <String, http.Response>{};
  final _etags = <String, String>{};
  var _next = 0;
  final requests = <String>[];

  // Tokens in circulation. A refresh token works once, as on the real server.
  final _access = <String>{};
  final _refresh = <String>{};
  var _tokenCounter = 0;

  http.Response _tokens() {
    final pair = {
      'access_token': 'access-${_tokenCounter++}',
      'refresh_token': 'refresh-${_tokenCounter++}',
    };
    _access.add(pair['access_token']!);
    _refresh.add(pair['refresh_token']!);
    return _json(200, pair);
  }

  /// Makes every access token stale, as when they expire.
  void expireAccessTokens() => _access.clear();

  /// Forgets all sessions, as when the server revokes them.
  void revokeSessions() {
    _access.clear();
    _refresh.clear();
  }

  Set<String> get refreshTokens => _refresh;

  http.Response _auth(String path, http.Request r) {
    switch (path) {
      case 'auth/login' || 'auth/register':
        return _tokens();
      case 'auth/refresh':
        final token = (jsonDecode(r.body) as Map)['refresh_token'];
        return _refresh.remove(token)
            ? _tokens()
            : _error(401, 'unauthenticated');
      case 'auth/logout':
        _refresh.remove((jsonDecode(r.body) as Map)['refresh_token']);
        return _json(204, null);
    }
    return _error(404, 'not_found');
  }

  /// Called before each request; throw to simulate a dropped connection.
  void Function(http.Request request)? beforeRequest;

  String _id() =>
      '00000000-0000-4000-8000-${(_next++).toString().padLeft(12, '0')}';
  String _now() => DateTime.now().toUtc().toIso8601String();
  Map<String, Map<String, dynamic>>? _collection(String name) => switch (name) {
    'plans' => plans,
    'sessions' => sessions,
    'users/me/measurements' => measurements,
    _ => null,
  };

  http.Response _json(
    int status,
    Object? body, {
    String? etag,
    bool replay = false,
  }) => http.Response(
    body == null ? '' : jsonEncode(body),
    status,
    headers: {'etag': ?etag, if (replay) 'idempotent-replayed': 'true'},
  );
  http.Response _error(int status, String code) => _json(status, {
    'error': {'code': code, 'message': code},
  });

  /// Marks [record] as changed on the server, as another device would.
  void touch(
    Map<String, dynamic> record, {
    DateTime? at,
    Map<String, dynamic>? with_,
  }) {
    record.addAll(with_ ?? {});
    record['updated_at'] = (at ?? DateTime.now()).toUtc().toIso8601String();
    _etags[record['id'] as String] = 'v${_next++}';
  }

  Map<String, dynamic> add(String collection, Map<String, dynamic> body) {
    final id = _id();
    final now = _now();
    final record = {
      'id': id,
      ...body,
      if (collection == 'plans')
        'exercises': [
          for (final e in body['exercises'] as List)
            {'id': _id(), ...e as Map<String, dynamic>},
        ],
      'created_at': now,
      'updated_at': now,
    };
    // Like the API, a session names its plan by ID only and every exercise
    // has notes.
    if (collection == 'sessions') record['plan_id'] = body['plan_id'];
    if (collection == 'plans' || collection == 'sessions') {
      record['exercises'] = [
        for (final e in record['exercises'] as List)
          {...e as Map<String, dynamic>, 'notes': e['notes'] ?? ''},
      ];
    }
    _collection(collection)![id] = record;
    _etags[id] = 'v${_next++}';
    return record;
  }

  Future<http.Response> handle(http.Request r) async {
    beforeRequest?.call(r);
    final path = r.url.path.replaceFirst('/api/v1/', '');
    requests.add('${r.method} $path');
    if (path.startsWith('auth/')) return _auth(path, r);
    if (!_access.contains(r.headers['Authorization']?.substring(7))) {
      return _error(401, 'unauthenticated');
    }
    final body = r.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(r.body) as Map<String, dynamic>;

    if (path == 'users' && r.method == 'POST') {
      final now = _now();
      profile = {
        'id': userId,
        'display_name': body['display_name'],
        'created_at': now,
        'updated_at': now,
      };
      _etags[userId] = 'v${_next++}';
      return _json(201, profile, etag: _etags[userId]);
    }
    if (path == 'users/me') {
      if (profile == null) return _error(403, 'profile_required');
      if (r.method == 'PUT') {
        if (r.headers['If-Match'] != _etags[userId]) {
          return _error(412, 'precondition_failed');
        }
        touch(profile!, with_: {'display_name': body['display_name']});
      }
      return _json(200, profile, etag: _etags[userId]);
    }

    final parts = path.split('/');
    final isItem = path.startsWith('users/me/measurements/')
        ? parts.length == 4
        : parts.length == 2;
    final name = isItem ? parts.sublist(0, parts.length - 1).join('/') : path;
    final id = isItem ? parts.last : null;
    final collection = _collection(name);
    if (collection == null) return _error(404, 'not_found');

    if (!isItem) {
      if (r.method == 'GET') {
        final all = collection.values.toList();
        final start = int.tryParse(r.url.queryParameters['cursor'] ?? '0')!;
        final limit = int.parse(r.url.queryParameters['limit']!);
        final page = all.skip(start).take(limit).toList();
        return _json(200, {
          'items': page,
          'limit': limit,
          'next_cursor': start + limit < all.length ? '${start + limit}' : null,
        });
      }
      // POST
      if (body.containsKey('id')) return _error(400, 'invalid_request');
      final key = r.headers['Idempotency-Key'];
      if (key != null && _replays.containsKey('$name/$key')) {
        final first = _replays['$name/$key']!;
        return _json(
          first.statusCode,
          jsonDecode(first.body),
          etag: first.headers['etag'],
          replay: true,
        );
      }
      final problem = _validateSession(name, body);
      if (problem != null) return problem;
      final record = add(name, body);
      final response = _json(201, record, etag: _etags[record['id']]);
      if (key != null) _replays['$name/$key'] = response;
      return response;
    }

    final record = collection[id];
    if (record == null) return _error(404, 'not_found');
    switch (r.method) {
      case 'GET':
        return _json(200, record, etag: _etags[id]);
      case 'PUT':
        if (r.headers['If-Match'] != _etags[id]) {
          return _error(412, 'precondition_failed');
        }
        if (name == 'plans' &&
            sessions.values.any((s) => s['plan_id'] == id) &&
            jsonEncode(_withoutIds(record['exercises'])) !=
                jsonEncode(_withoutIds(body['exercises']))) {
          return _error(409, 'plan_in_use');
        }
        final problem = _validateSession(name, body);
        if (problem != null) return problem;
        final replaced = add(name, body);
        collection.remove(replaced['id']);
        _etags.remove(replaced['id']);
        touch(
          record
            ..clear()
            ..addAll({
              ...replaced,
              'id': id,
              'created_at': replaced['created_at'],
            }),
        );
        return _json(200, record, etag: _etags[id]);
      case 'DELETE':
        if (name == 'plans' && sessions.values.any((s) => s['plan_id'] == id)) {
          return _error(409, 'resource_in_use');
        }
        collection.remove(id);
        return _json(204, null);
    }
    return _error(405, 'method_not_allowed');
  }

  /// Exercises as the client sees them, ignoring server-issued entry IDs.
  Object? _withoutIds(Object? exercises) => [
    for (final e in exercises as List)
      {...e as Map<String, dynamic>}..remove('id'),
  ];

  http.Response? _validateSession(String name, Map<String, dynamic> body) {
    if (name != 'sessions') return null;
    final plan = plans[body['plan_id']];
    for (final e in body['exercises'] as List) {
      final link = (e as Map)['plan_exercise_id'];
      if (link != null &&
          !((plan?['exercises'] as List?) ?? []).any(
            (p) => (p as Map)['id'] == link,
          )) {
        return _error(400, 'validation_failed');
      }
    }
    return null;
  }
}
