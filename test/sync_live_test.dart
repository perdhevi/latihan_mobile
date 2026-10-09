// Runs the sync against a real fitness-api. Skipped unless the URL is given:
//
//   flutter test test/sync_live_test.dart --dart-define=SYNC_LIVE_URL=http://localhost:8080/api/v1/
//
// It registers a new throwaway account each run, so it leaves that account's
// data on the server.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latihan_mobile/core/cloud_sync.dart';
import 'package:latihan_mobile/core/credential_store.dart';
import 'package:latihan_mobile/core/database.dart';
import 'package:latihan_mobile/core/fitness_api.dart';
import 'package:latihan_mobile/core/fitness_store.dart';
import 'package:latihan_mobile/core/sync_service.dart';
import 'package:latihan_mobile/features/sessions/session.dart';

const liveUrl = String.fromEnvironment('SYNC_LIVE_URL');

void main() {
  test('syncs a full workout history with the real server', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final api = FitnessApi(liveUrl);
    addTearDown(api.close);
    await api.signIn(
      'sync-$stamp@example.test',
      'Pw-$stamp-aA1!',
      register: true,
    );

    final db = AppDatabase(NativeDatabase.memory());
    final store = FitnessStore(db);
    addTearDown(store.dispose);
    await store.load();
    await store.saveProfileName('Live Test');
    await store.savePlan(
      Plan(
        id: 'p',
        name: 'Push day',
        exercises: [
          Exercise(name: 'Bench', sets: [const ExerciseSet(5, 60)]),
          Exercise(name: 'Run', minutes: 15),
        ],
      ),
    );
    await store.addMeasurement({
      'measured_at': '2026-10-01T08:00:00.000Z',
      'weight_kg': 70.5,
    });
    final plan = store.plans.single;
    await store.start(plan);
    await store.updateActive(
      exercises: [
        Exercise(
          planExerciseId: plan.exercises.first.id,
          name: 'Bench',
          sets: [const ExerciseSet(5, 62.5)],
        ),
        Exercise(name: 'Run', minutes: 20, avgBpm: 150),
      ],
    );
    await store.finish();

    final first = await SyncService(db, api).sync();
    expect(first.failures, isEmpty, reason: first.failures.join('\n'));
    expect(first.pushed, 4);

    final remotePlan = (await api.listAll('plans')).single;
    final remoteSession = (await api.listAll('sessions')).single;
    expect(remoteSession['plan_id'], remotePlan['id']);
    final linked = (remoteSession['exercises'] as List).first as Map;
    expect(
      linked['plan_exercise_id'],
      (remotePlan['exercises'] as List).first['id'],
    );
    expect(
      (await api.listAll('users/me/measurements')).single['weight_kg'],
      70.5,
    );

    // Nothing left to do: a second sync makes no changes.
    final second = await SyncService(db, api).sync();
    expect(
      [second.pushed, second.pulled, second.removed, second.conflicts],
      [0, 0, 0, 0],
    );

    // A second device (empty database) receives everything.
    final other = AppDatabase(NativeDatabase.memory());
    final otherStore = FitnessStore(other);
    addTearDown(otherStore.dispose);
    final received = await SyncService(other, api).sync();
    expect(received.failures, isEmpty, reason: received.failures.join('\n'));
    await otherStore.load();
    expect(otherStore.history.single.exercises.last.avgBpm, 150);
    expect(otherStore.plans.single.exercises, hasLength(2));
    expect(otherStore.profileName, 'Live Test');

    // Local deletion and edit propagate.
    await store.deleteMeasurement(store.measurements.single['id'] as String);
    await store.savePlan(
      Plan(
        id: 'p',
        name: 'Push day v2',
        exercises: plan.exercises.take(1).toList(),
      ),
    );
    final third = await SyncService(db, api).sync();
    expect(third.failures, isEmpty, reason: third.failures.join('\n'));
    expect(await api.listAll('users/me/measurements'), isEmpty);
    // The server freezes the used plan, so the edit arrives as a second plan
    // and the first stays for the existing session.
    final plans = await api.listAll('plans');
    expect(
      plans.map((p) => p['name']),
      unorderedEquals(['Push day', 'Push day v2']),
    );
    final again = await SyncService(db, api).sync();
    expect([again.pushed, again.pulled, again.failures.length], [0, 0, 0]);
    await store.load();
    expect(store.plans, hasLength(1));
  }, skip: liveUrl.isEmpty ? 'set SYNC_LIVE_URL to run' : false);

  test('a stored session resumes and syncs after a restart', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final db = AppDatabase(NativeDatabase.memory());
    final store = FitnessStore(db);
    addTearDown(store.dispose);
    await store.load();
    await store.saveProfileName('Resume Test');
    final credentials = MemoryCredentialStore();

    final first = CloudSync(store, credentials: credentials);
    addTearDown(first.dispose);
    await first.signIn(
      liveUrl,
      'resume-$stamp@example.test',
      'Pw-$stamp-aA1!',
      register: true,
    );
    expect(first.needsProfile, isTrue);
    await first.createProfile('Resume Test');
    await first.sync();
    expect(first.problem, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final stored = credentials.value!.refreshToken;
    first.dispose();

    // "Restart": a new controller with only what was stored.
    final second = CloudSync(store, credentials: credentials);
    addTearDown(second.dispose);
    await second.restore();
    expect(second.signedIn, isTrue);
    expect(second.problem, isNull, reason: second.problem);
    expect(second.lastSyncAt, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(credentials.value!.refreshToken, isNot(stored));

    await second.signOut();
    expect(credentials.value, isNull);
    expect(store.profileName, 'Resume Test');
  }, skip: liveUrl.isEmpty ? 'set SYNC_LIVE_URL to run' : false);
}
