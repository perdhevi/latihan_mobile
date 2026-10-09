import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latihan_mobile/core/cloud_sync.dart';
import 'package:latihan_mobile/core/credential_store.dart';
import 'package:latihan_mobile/core/database.dart';
import 'package:latihan_mobile/core/fitness_api.dart';
import 'package:latihan_mobile/core/fitness_store.dart';
import 'package:latihan_mobile/features/sessions/session.dart';

import 'support/fake_server.dart';

void main() {
  late AppDatabase db;
  late FitnessStore store;
  late FakeServer server;
  late MemoryCredentialStore credentials;
  var offline = false;

  const url = 'https://fitness.example/api/v1/';
  const quick = Duration(milliseconds: 40);

  FitnessApi apiFor(
    FakeServer s,
    String address,
    String? token,
    void Function(String?) onToken,
  ) => FitnessApi(
    address,
    refreshToken: token,
    onRefreshToken: onToken,
    client: MockClient((r) async {
      if (offline) throw http.ClientException('offline');
      return s.handle(r);
    }),
  );

  CloudSync make({
    Duration debounce = quick,
    Duration minInterval = Duration.zero,
    FakeServer? on,
  }) {
    final target = on ?? server;
    final cloud = CloudSync(
      store,
      credentials: credentials,
      debounce: debounce,
      minInterval: minInterval,
      apiFactory: (address, token, onToken) =>
          apiFor(target, address, token, onToken),
    );
    addTearDown(cloud.dispose);
    return cloud;
  }

  int syncs() => server.requests.where((r) => r == 'GET users/me').length;
  Future<void> settle() => Future.delayed(const Duration(milliseconds: 250));

  Map<String, dynamic> profileOf(String id, String name) => {
    'id': id,
    'display_name': name,
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
  };

  setUp(() async {
    offline = false;
    db = AppDatabase(NativeDatabase.memory());
    store = FitnessStore(db);
    await store.load();
    addTearDown(store.dispose);
    server = FakeServer();
    credentials = MemoryCredentialStore();
    await store.saveProfileName('Alex');
  });

  Future<void> signedIn(CloudSync cloud) async {
    server.profile = profileOf('user-1', 'Alex');
    await cloud.signIn(url, 'a@example.com', 'password');
  }

  test(
    'signing in stores the session; signing out clears it and keeps local data',
    () async {
      final cloud = make();
      await signedIn(cloud);
      await settle();
      expect(credentials.value!.url, url);
      expect(credentials.value!.refreshToken, startsWith('refresh-'));
      expect(cloud.signedIn, isTrue);

      await store.addMeasurement({
        'measured_at': '2026-10-01T08:00:00.000Z',
        'weight_kg': 70,
      });
      await cloud.signOut();
      expect(credentials.value, isNull);
      expect(cloud.signedIn, isFalse);
      expect(server.refreshTokens, isEmpty); // revoked on the server too
      await store.load();
      expect(store.measurements, hasLength(1));
    },
  );

  test(
    'a stored session resumes without a password, rotates its token and syncs',
    () async {
      final first = make();
      await signedIn(first);
      await settle();
      final stored = credentials.value!.refreshToken;
      first.dispose();

      final cloud = make();
      await cloud.restore();
      expect(cloud.signedIn, isTrue);
      expect(cloud.problem, isNull);
      expect(cloud.lastSyncAt, isNotNull);
      await settle();
      // The single-use token was exchanged and the new one stored.
      expect(credentials.value!.refreshToken, isNot(stored));
      expect(server.requests, contains('POST auth/refresh'));
    },
  );

  test('an expired access token is refreshed transparently', () async {
    final cloud = make();
    await signedIn(cloud);
    server.expireAccessTokens();
    await store.addMeasurement({
      'measured_at': '2026-10-01T08:00:00.000Z',
      'weight_kg': 70,
    });
    await settle();
    expect(server.measurements, hasLength(1));
    expect(cloud.problem, isNull);
  });

  test(
    'a revoked session signs out, keeps data and forgets the credentials',
    () async {
      final first = make();
      await signedIn(first);
      await settle();
      first.dispose();
      server.revokeSessions();

      final cloud = make();
      await cloud.restore();
      expect(cloud.signedIn, isFalse);
      expect(cloud.problem, contains('Sign in'));
      expect(credentials.value, isNull);
      expect(store.profileName, 'Alex');
    },
  );

  test(
    'starting offline keeps the session and syncs once back online',
    () async {
      final first = make();
      await signedIn(first);
      await settle();
      first.dispose();

      offline = true;
      final cloud = make();
      await cloud.restore();
      expect(cloud.signedIn, isTrue);
      expect(cloud.problem, contains('safe on this device'));
      expect(credentials.value, isNotNull);

      offline = false;
      await cloud.sync();
      expect(cloud.problem, isNull);
      expect(cloud.lastSyncAt, isNotNull);
    },
  );

  test('a burst of changes causes one sync after they settle', () async {
    final cloud = make();
    await signedIn(cloud);
    server.requests.clear();
    for (var i = 0; i < 3; i++) {
      await store.addMeasurement({
        'measured_at': '2026-10-0${i + 1}T08:00:00.000Z',
        'weight_kg': 70.0 + i,
      });
    }
    expect(syncs(), 0); // not yet
    await settle();
    expect(syncs(), 1);
    expect(server.measurements, hasLength(3));
    expect(cloud.lastResult, contains('Sent 3'));
  });

  test('edits to the session in progress do not trigger a sync', () async {
    final cloud = make();
    await signedIn(cloud);
    server.requests.clear();
    await store.start();
    await store.updateActive(exercises: [Exercise(name: 'Run', minutes: 5)]);
    await settle();
    expect(syncs(), 0);
    await store.finish();
    await settle();
    expect(syncs(), 1);
    expect(server.sessions, hasLength(1));
  });

  test(
    'returning to the app syncs, but not more often than the interval',
    () async {
      final cloud = make(minInterval: const Duration(minutes: 5));
      await signedIn(cloud);
      server.requests.clear();
      cloud.resumed();
      await settle();
      expect(syncs(), 1);
      cloud.resumed();
      await settle();
      expect(syncs(), 1);
    },
  );

  test('nothing syncs while signed out', () async {
    final cloud = make();
    cloud.resumed();
    await store.addMeasurement({
      'measured_at': '2026-10-01T08:00:00.000Z',
      'weight_kg': 70,
    });
    await settle();
    expect(server.requests, isEmpty);
    expect(cloud.signedIn, isFalse);
  });

  test(
    'a different account is flagged by automatic syncs without touching data',
    () async {
      final first = make();
      await signedIn(first);
      await first.sync();
      first.dispose();

      final other = FakeServer(userId: 'user-2')
        ..profile = profileOf('user-2', 'Sam');
      final cloud = make(on: other);
      await cloud.signIn(url, 'b@example.com', 'password');
      await cloud.sync();
      expect(cloud.accountConflict, isTrue);
      expect(cloud.problem, contains('different cloud account'));
      expect(store.profileName, 'Alex');

      // Resolved by the user: keep and upload.
      await cloud.sync(onAccountMismatch: () async => false);
      expect(cloud.accountConflict, isFalse);
      expect(cloud.problem, isNull);
    },
  );

  test('an account without a cloud profile waits for one first', () async {
    final cloud = make();
    await cloud.signIn(url, 'a@example.com', 'password');
    expect(cloud.needsProfile, isTrue);
    expect(await cloud.sync(), isNull);
    await cloud.createProfile('Alex');
    expect(cloud.needsProfile, isFalse);
    expect(await cloud.sync(), isNotNull);
  });
}
