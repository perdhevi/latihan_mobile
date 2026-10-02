import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latihan_mobile/core/fitness_api.dart';

void main() {
  test(
    'login, owner profile, cursor encoding and token refresh match Go contract',
    () async {
      final requests = <http.Request>[];
      var expired = true;
      final api = FitnessApi(
        'https://fitness.example/api/v1',
        client: MockClient((r) async {
          requests.add(r);
          if (r.url.path.endsWith('/auth/login')) {
            expect(jsonDecode(r.body), {
              'email': 'alex@example.com',
              'password': 'password',
            });
            expect(r.headers.containsKey('Authorization'), isFalse);
            return http.Response(
              '{"access_token":"old","refresh_token":"refresh"}',
              200,
            );
          }
          if (r.url.path.endsWith('/auth/refresh')) {
            expect(jsonDecode(r.body), {'refresh_token': 'refresh'});
            return http.Response(
              '{"access_token":"new","refresh_token":"rotated"}',
              200,
            );
          }
          if (expired) {
            expired = false;
            return http.Response(
              '{"error":{"code":"unauthenticated","message":"Expired"}}',
              401,
            );
          }
          expect(r.headers['Authorization'], 'Bearer new');
          if (r.url.path.endsWith('/users/me')) {
            return http.Response('{"display_name":"Alex"}', 200);
          }
          expect(r.url.queryParameters, {'limit': '20', 'cursor': 'a+/='});
          return http.Response('{"items":[],"next_cursor":null}', 200);
        }),
      );
      addTearDown(api.close);
      await api.signIn(' alex@example.com ', 'password');
      expect((await api.profile())['display_name'], 'Alex');
      expect((await api.sessions(cursor: 'a+/='))['items'], isEmpty);
      expect(requests.length, 5);
    },
  );

  test('profile-required error is exposed and sign-out clears credentials on failure', () async {
    final api = FitnessApi(
      'https://fitness.example/api/v1/',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/auth/register')) {
          return http.Response(
            '{"access_token":"token","refresh_token":"refresh"}',
            201,
          );
        }
        return http.Response(
          '{"error":{"code":"profile_required","message":"Create a profile"}}',
          403,
        );
      }),
    );
    addTearDown(api.close);
    await api.signIn('alex@example.com', 'password', register: true);
    await expectLater(
      api.profile(),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'profile_required'),
      ),
    );
    await expectLater(api.signOut(), throwsA(isA<ApiException>()));
    expect(api.signedIn, isFalse);
    await expectLater(api.sessions(), throwsA(isA<ApiException>()));
  });
}
