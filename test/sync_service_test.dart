import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latihan_mobile/core/database.dart';
import 'package:latihan_mobile/core/fitness_api.dart';
import 'package:latihan_mobile/core/fitness_store.dart';
import 'package:latihan_mobile/core/sync_service.dart';
import 'package:latihan_mobile/features/sessions/session.dart';

import 'support/fake_server.dart';

void main() {
  late AppDatabase db;
  late FakeServer server;
  late FitnessApi api;
  late FitnessStore store;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    server = FakeServer();
    api = FitnessApi(
      'https://fitness.example/api/v1',
      client: MockClient(server.handle),
    );
    await api.signIn('a@example.com', 'password');
    store = FitnessStore(db);
    await store.load();
    addTearDown(store.dispose);
    addTearDown(api.close);
  });

  Future<SyncReport> sync() => SyncService(db, api).sync();

  Future<void> logRun({Plan? plan, String? entry}) async {
    await store.start(plan);
    await store.updateActive(
      exercises: [
        Exercise(planExerciseId: entry, name: 'Run', minutes: 20, avgBpm: 140),
      ],
    );
    await store.finish();
  }

  test('first sync uploads everything once with server IDs; repeating it sends nothing', () async {
    await store.saveProfileName('Alex');
    await store.savePlan(
      Plan(
        id: 'plan-1',
        name: 'Cardio',
        exercises: [Exercise(name: 'Run', minutes: 20)],
      ),
    );
    await store.addMeasurement({
      'measured_at': '2026-10-01T08:00:00.000Z',
      'weight_kg': 70.5,
    });
    await logRun(
      plan: store.plans.single,
      entry: store.plans.single.exercises.single.id,
    );

    final first = await sync();
    expect(first.failures, isEmpty);
    expect(first.pushed, 4); // profile, plan, session, measurement
    expect(server.profile!['display_name'], 'Alex');
    expect(server.plans, hasLength(1));
    expect(server.measurements.values.single['weight_kg'], 70.5);

    // The session reached the server linked to the server's copy of the plan,
    // not the local IDs.
    final remotePlan = server.plans.values.single;
    final remoteSession = server.sessions.values.single;
    expect(remoteSession['plan_id'], remotePlan['id']);
    expect(
      (remoteSession['exercises'] as List).single['plan_exercise_id'],
      (remotePlan['exercises'] as List).single['id'],
    );

    server.requests.clear();
    final second = await sync();
    expect(
      [second.pushed, second.pulled, second.removed, second.conflicts],
      [0, 0, 0, 0],
    );
    expect(server.requests.where((r) => !r.startsWith('GET')), isEmpty);
    expect(server.plans, hasLength(1));
    expect(server.sessions, hasLength(1));
  });

  test(
    'records created on the server are pulled with their IDs, across pages',
    () async {
      await store.saveProfileName('Alex');
      for (var i = 0; i < 120; i++) {
        server.add('sessions', {
          'name': 'Session $i',
          'notes': '',
          'performed_at': '2026-09-01T07:00:00Z',
          'plan_id': null,
          'exercises': [
            {
              'name': 'Squat',
              'kind': 'strength',
              'sets': [
                {'repetitions': 5, 'weight_kg': 100},
              ],
            },
          ],
        });
      }
      server.add('users/me/measurements', {
        'measured_at': '2026-09-01T07:00:00Z',
        'waist_cm': 80,
      });

      final report = await sync();
      expect(report.pulled, 121); // 120 sessions + 1 measurement
      await store.load();
      expect(store.history, hasLength(120));
      expect(store.history.first.exercises.single.sets.single.weightKg, 100);
      expect(store.measurements.single['waist_cm'], 80);
      expect((await sync()).pulled, 0);
    },
  );

  test('a local edit is sent, a remote edit is received, deletions propagate both ways', () async {
    await store.saveProfileName('Alex');
    await store.savePlan(
      Plan(
        id: 'a',
        name: 'Push',
        exercises: [
          Exercise(name: 'Bench', sets: [const ExerciseSet(5, 60)]),
        ],
      ),
    );
    await store.savePlan(
      Plan(
        id: 'b',
        name: 'Pull',
        exercises: [
          Exercise(name: 'Row', sets: [const ExerciseSet(8, 50)]),
        ],
      ),
    );
    await store.addMeasurement({
      'measured_at': '2026-10-01T08:00:00.000Z',
      'weight_kg': 70,
    });
    await sync();

    // Local edit of plan a; remote edit of plan b; local delete of the measurement.
    await store.savePlan(
      Plan(
        id: 'a',
        name: 'Push v2',
        exercises: [
          Exercise(name: 'Bench', sets: [const ExerciseSet(5, 65)]),
        ],
      ),
    );
    final remoteB = server.plans.values.firstWhere((p) => p['name'] == 'Pull');
    server.touch(remoteB, with_: {'name': 'Pull v2'});
    await store.deleteMeasurement(store.measurements.single['id'] as String);

    final report = await sync();
    expect(report.failures, isEmpty);
    expect(
      server.plans.values.map((p) => p['name']),
      containsAll(['Push v2', 'Pull v2']),
    );
    expect(server.measurements, isEmpty);
    await store.load();
    expect(store.plans.map((p) => p.name), containsAll(['Push v2', 'Pull v2']));

    // Deleted on the server: the clean local copy goes away.
    server.plans.remove(
      server.plans.values.firstWhere((p) => p['name'] == 'Pull v2')['id'],
    );
    final removal = await sync();
    expect(removal.removed, 1);
    await store.load();
    expect(store.plans.map((p) => p.name), ['Push v2']);
  });

  test('a change on both sides keeps the newer one', () async {
    await store.saveProfileName('Alex');
    await store.savePlan(
      Plan(
        id: 'a',
        name: 'Original',
        exercises: [Exercise(name: 'Run', minutes: 10)],
      ),
    );
    await sync();
    final remote = server.plans.values.single;

    await store.savePlan(
      Plan(
        id: 'a',
        name: 'Local edit',
        exercises: [Exercise(name: 'Run', minutes: 10)],
      ),
    );
    server.touch(
      remote,
      at: DateTime.now().subtract(const Duration(hours: 1)),
      with_: {'name': 'Remote edit'},
    );
    var report = await sync();
    expect(report.conflicts, 1);
    expect(remote['name'], 'Local edit');

    server.touch(
      remote,
      at: DateTime.now().add(const Duration(hours: 1)),
      with_: {'name': 'Newer remote'},
    );
    await store.savePlan(
      Plan(
        id: 'a',
        name: 'Older local',
        exercises: [Exercise(name: 'Run', minutes: 10)],
      ),
    );
    report = await sync();
    expect(report.conflicts, 1);
    await store.load();
    expect(store.plans.single.name, 'Newer remote');
  });

  test('an interrupted upload resumes without duplicates', () async {
    await store.saveProfileName('Alex');
    for (var i = 0; i < 3; i++) {
      await store.addMeasurement({
        'measured_at': '2026-10-0${i + 1}T08:00:00.000Z',
        'weight_kg': 70.0 + i,
      });
    }
    // The connection drops on the third measurement, after the server has
    // stored it but before the client sees the response.
    var posts = 0;
    var drop = true;
    final flaky = FitnessApi(
      'https://fitness.example/api/v1',
      client: MockClient((r) async {
        final response = await server.handle(r);
        if (drop &&
            r.method == 'POST' &&
            r.url.path.endsWith('measurements') &&
            ++posts == 3) {
          throw http.ClientException('connection lost');
        }
        return response;
      }),
    );
    await flaky.signIn('a@example.com', 'password');
    addTearDown(flaky.close);
    await expectLater(
      SyncService(db, flaky).sync(),
      throwsA(isA<http.ClientException>()),
    );
    expect(server.measurements, hasLength(3));

    // The retry carries the same Idempotency-Key, so the server hands back
    // the record it already made instead of a fourth.
    drop = false;
    final report = await SyncService(db, flaky).sync();
    expect(report.failures, isEmpty);
    expect(report.pushed, 1);
    expect(server.measurements, hasLength(3));
    expect((await sync()).pushed, 0);
  });

  test(
    'a record the server refuses is reported and does not stop the sync',
    () async {
      await store.saveProfileName('Alex');
      await store.savePlan(
        Plan(
          id: 'a',
          name: 'Plan',
          exercises: [Exercise(name: 'Run', minutes: 10)],
        ),
      );
      await store.addMeasurement({
        'measured_at': '2026-10-01T08:00:00.000Z',
        'weight_kg': 70,
      });
      final refusing = FitnessApi(
        'https://fitness.example/api/v1',
        client: MockClient((r) async {
          if (r.method == 'POST' && r.url.path.endsWith('/plans')) {
            return http.Response(
              '{"error":{"code":"validation_failed","message":"name is required"}}',
              400,
            );
          }
          return server.handle(r);
        }),
      );
      await refusing.signIn('a@example.com', 'password');
      addTearDown(refusing.close);
      final report = await SyncService(db, refusing).sync();
      expect(report.failures.single, contains('plan a'));
      expect(server.measurements, hasLength(1));
    },
  );

  test('editing a plan the server froze uploads it as a new plan', () async {
    await store.saveProfileName('Alex');
    await store.savePlan(
      Plan(
        id: 'a',
        name: 'Push',
        exercises: [
          Exercise(name: 'Bench', sets: [const ExerciseSet(5, 60)]),
        ],
      ),
    );
    await logRun(plan: store.plans.single);
    await sync();
    final oldRemote = server.plans.keys.single;

    // A rename alone is accepted in place.
    await store.savePlan(
      Plan(id: 'a', name: 'Push day', exercises: store.plans.single.exercises),
    );
    expect((await sync()).failures, isEmpty);
    expect(server.plans.keys.single, oldRemote);
    expect(server.plans[oldRemote]!['name'], 'Push day');

    // Changing the exercises is not: the server keeps the old plan for the
    // session that used it and gets the edit as a second plan.
    await store.savePlan(
      Plan(
        id: 'a',
        name: 'Push day',
        exercises: [
          Exercise(name: 'Bench', sets: [const ExerciseSet(5, 80)]),
        ],
      ),
    );
    final report = await sync();
    expect(report.failures, isEmpty);
    expect(server.plans, hasLength(2));
    expect(
      server.plans[oldRemote]!['exercises'][0]['sets'][0]['weight_kg'],
      60,
    );

    // The old server plan is not pulled back as a duplicate, and nothing
    // further is sent.
    await store.load();
    expect(store.plans, hasLength(1));
    expect(store.plans.single.exercises.single.sets.single.weightKg, 80);
    final again = await sync();
    expect([again.pushed, again.pulled, again.failures.length], [0, 0, 0]);
    expect(server.plans, hasLength(2));
  });

  test('a plan the server still uses stays queued for deletion', () async {
    await store.saveProfileName('Alex');
    await store.savePlan(
      Plan(
        id: 'a',
        name: 'Plan',
        exercises: [Exercise(name: 'Run', minutes: 10)],
      ),
    );
    await logRun(plan: store.plans.single);
    await sync();

    await store.deletePlan('a');
    final report = await sync();
    expect(report.failures.single, contains('plan'));
    expect(server.plans, hasLength(1));
    expect(await db.select(db.pendingDeletes).get(), hasLength(1));

    server.sessions.clear();
    expect((await sync()).failures, isEmpty);
    expect(server.plans, isEmpty);
    expect(await db.select(db.pendingDeletes).get(), isEmpty);
  });

  Future<(FakeServer, FitnessApi)> secondAccount() async {
    final other = FakeServer(userId: 'user-2')
      ..profile = {
        'id': 'user-2',
        'display_name': 'Sam',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      };
    final otherApi = FitnessApi(
      'https://fitness.example/api/v1',
      client: MockClient(other.handle),
    );
    await otherApi.signIn('b@example.com', 'password');
    addTearDown(otherApi.close);
    return (other, otherApi);
  }

  Future<void> syncedAsAlex() async {
    await store.saveProfileName('Alex');
    await store.addMeasurement({
      'measured_at': '2026-10-01T08:00:00.000Z',
      'weight_kg': 70,
    });
    await sync();
  }

  test('a second account is refused until the user chooses', () async {
    await syncedAsAlex();
    final (other, otherApi) = await secondAccount();
    await expectLater(
      SyncService(db, otherApi).sync(),
      throwsA(isA<SyncAccountMismatch>()),
    );
    expect(other.measurements, isEmpty);
  });

  test(
    'switching account and erasing leaves only the new account data',
    () async {
      await syncedAsAlex();
      final (other, otherApi) = await secondAccount();
      await SyncService.unlinkAccount(db, eraseData: true);
      await SyncService(db, otherApi).sync();
      await store.load();
      expect(store.profileName, 'Sam');
      expect(store.measurements, isEmpty);
      expect(other.measurements, isEmpty);
      expect(server.measurements, hasLength(1)); // first account untouched
    },
  );

  test(
    'switching account and keeping uploads local data to the new one',
    () async {
      await syncedAsAlex();
      final (other, otherApi) = await secondAccount();
      await SyncService.unlinkAccount(db);
      final report = await SyncService(db, otherApi).sync();
      expect(report.failures, isEmpty);
      expect(other.measurements, hasLength(1));
    },
  );

  test(
    'without a name there is nothing to create the cloud profile from',
    () async {
      await expectLater(sync(), throwsA(isA<SyncException>()));
    },
  );

  test('an unsynced profile name edit reaches the server and a remote one comes back', () async {
    await store.saveProfileName('Alex');
    await sync();
    await store.saveProfileName('Alexander');
    await sync();
    expect(server.profile!['display_name'], 'Alexander');

    server.touch(server.profile!, with_: {'display_name': 'Al'});
    await sync();
    await store.load();
    expect(store.profileName, 'Al');
  });

  test('sessions in progress are never uploaded', () async {
    await store.saveProfileName('Alex');
    await store.start();
    await store.updateActive(exercises: [Exercise(name: 'Run', minutes: 5)]);
    await sync();
    expect(server.sessions, isEmpty);
    expect((await db.select(db.sessions).get()).single.active, isTrue);
  });
}
