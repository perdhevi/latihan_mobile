import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:drift/native.dart';
import 'package:latihan_mobile/core/database.dart';
import 'package:latihan_mobile/main.dart';
import 'package:latihan_mobile/features/sessions/session_editor.dart';
import 'package:latihan_mobile/core/fitness_store.dart';
import 'package:latihan_mobile/features/sessions/session.dart';
import 'package:latihan_mobile/features/ideas/ideas_repository.dart';

void main() {
  AppDatabase memory() => AppDatabase(NativeDatabase.memory());

  test('plan snapshot and active results persist separately', () async {
    final db = memory();
    addTearDown(db.close);
    final store = FitnessStore(db);
    await store.load();
    await store.savePlan(
      Plan(
        id: 'plan',
        name: 'Cardio day',
        exercises: [Exercise(name: 'Run', minutes: 20, avgBpm: 140)],
      ),
    );
    final target = store.plans.single.exercises.single;
    await store.start(store.plans.single);
    expect(store.active!.name, 'Cardio day');
    expect(store.active!.exercises, isEmpty);
    await store.updateActive(
      name: 'Morning',
      exercises: [
        Exercise(planExerciseId: target.id, name: 'Run', minutes: 22),
      ],
    );
    // Editing the plan issues new entry IDs but leaves the snapshot alone.
    await store.savePlan(
      Plan(
        id: 'plan',
        name: 'Cardio day',
        exercises: [Exercise(name: 'Run', minutes: 45)],
      ),
    );
    expect(store.plans.single.exercises.single.id, isNot(target.id));
    final restored = FitnessStore(db);
    await restored.load();
    expect(restored.error, isNull);
    expect(restored.active!.name, 'Morning');
    expect(restored.active!.date, store.active!.date);
    expect(restored.active!.exercises.single.minutes, 22);
    expect(restored.active!.exercises.single.planExerciseId, target.id);
    expect(restored.active!.plan!.exercises.single.minutes, 20);
    expect(restored.active!.plan!.exercises.single.id, target.id);
    expect(restored.history, isEmpty);
    await restored.finish();
    final finished = FitnessStore(db);
    await finished.load();
    expect(finished.active, isNull);
    expect(finished.history.single.plan!.id, 'plan');
    expect(finished.plans.single.exercises.single.minutes, 45);
    await finished.deletePlan('plan');
    final emptied = FitnessStore(db);
    await emptied.load();
    expect(emptied.plans, isEmpty);
    expect(emptied.history.single.plan!.name, 'Cardio day');
  });

  test(
    'empty sessions cannot finish; profile and measurements survive reload',
    () async {
      final db = memory();
      addTearDown(db.close);
      final store = FitnessStore(db);
      await store.load();
      await store.start();
      await expectLater(store.finish(), throwsStateError);
      expect(store.active, isNotNull);
      await store.saveProfileName('Al');
      await store.saveProfileName('Alex');
      final older = DateTime.utc(2026, 1, 1).toIso8601String();
      final newer = DateTime.utc(2026, 2, 1).toIso8601String();
      await store.addMeasurement({'measured_at': older, 'weight_kg': 72.5});
      await store.addMeasurement({
        'measured_at': newer,
        'weight_kg': 71.0,
        'body_fat_percent': 18.0,
      });
      final restored = FitnessStore(db);
      await restored.load();
      expect(restored.profileName, 'Alex');
      expect(restored.measurements, store.measurements);
      expect(restored.measurements.first, {
        'id': isA<String>(),
        'measured_at': newer,
        'weight_kg': 71.0,
        'body_fat_percent': 18.0,
      });
      await restored.deleteMeasurement(restored.measurements.first['id']);
      final after = FitnessStore(db);
      await after.load();
      expect(after.measurements.single['weight_kg'], 72.5);
    },
  );

  test('export holds everything on the device as JSON', () async {
    final db = memory();
    addTearDown(db.close);
    final store = FitnessStore(db);
    await store.load();
    expect((await store.export())['user'], isNull);
    await store.saveProfileName('Alex');
    await store.addMeasurement({
      'measured_at': DateTime.utc(2026, 1, 1).toIso8601String(),
      'weight_kg': 72.5,
    });
    await store.savePlan(
      Plan(
        id: 'plan',
        name: 'Legs',
        exercises: [
          Exercise(name: 'Squat', sets: const [ExerciseSet(5, 80)]),
        ],
      ),
    );
    await store.start(store.plans.single);
    await store.updateActive(
      exercises: [store.plans.single.exercises.single.logged()],
    );
    await store.finish();
    await store.start();
    final export =
        jsonDecode(jsonEncode(await store.export())) as Map<String, dynamic>;
    expect(export['format'], 'latihan-mobile-export/1');
    expect(DateTime.parse(export['exported_at']).isUtc, isTrue);
    expect(export['user']['display_name'], 'Alex');
    expect(export['measurements'].single['weight_kg'], 72.5);
    expect(export['plans'].single['exercises'].single['sets'], [
      {'repetitions': 5, 'weight_kg': 80.0},
    ]);
    final session = export['sessions'].single;
    expect(session['plan_id'], 'plan');
    expect(
      session['exercises'].single['plan_exercise_id'],
      session['plan_snapshot']['exercises'].single['id'],
    );
    expect(export['active_session']['name'], 'Workout');
    for (final record in [
      export['user'],
      export['measurements'].single,
      export['plans'].single,
      session,
    ]) {
      expect(DateTime.parse(record['created_at']).isUtc, isTrue);
      expect(DateTime.parse(record['updated_at']).isUtc, isTrue);
    }
  });

  test('sessions decode from the API contract', () {
    final session = WorkoutSession.fromJson({
      'id': '0b0e7a52-6a4f-4c0e-9d5e-0d6f3d1c2a11',
      'user_id': '5f2b3c1e-8f0a-4a57-9b1d-2f7a6f0c9e33',
      'name': 'Leg day',
      'notes': '',
      'performed_at': '2026-03-01T10:00:00Z',
      'plan_id': 'p',
      'exercises': [
        {
          'plan_exercise_id': 'e1',
          'name': 'Squat',
          'kind': 'strength',
          'sets': [
            {'repetitions': 5, 'weight_kg': 82.5},
            {'repetitions': 12, 'weight_kg': 0},
          ],
          'minutes': null,
          'avg_bpm': null,
        },
        {
          'name': 'Row',
          'kind': 'cardio',
          'sets': null,
          'minutes': 12.5,
          'avg_bpm': 150,
        },
      ],
      'plan_snapshot': {
        'id': 'p',
        'user_id': '5f2b3c1e-8f0a-4a57-9b1d-2f7a6f0c9e33',
        'name': 'Legs',
        'notes': '',
        'exercises': [
          {
            'id': 'e1',
            'name': 'Squat',
            'kind': 'strength',
            'sets': [
              {'repetitions': 5, 'weight_kg': 80},
            ],
            'minutes': null,
            'avg_bpm': null,
          },
        ],
        'created_at': '2026-02-01T10:00:00Z',
        'updated_at': '2026-02-01T10:00:00Z',
      },
      'created_at': '2026-03-01T11:00:00Z',
      'updated_at': '2026-03-01T11:00:00Z',
    });
    expect(session.date.toUtc(), DateTime.utc(2026, 3, 1, 10));
    expect(session.exercises[0].summary, '2 sets · 5 reps · 82.5 kg, 12 reps');
    expect(session.exercises[1].summary, '12.5 min · 150 BPM');
    expect(
      session.exercises[0].planExerciseId,
      session.plan!.exercises.single.id,
    );
  });

  test(
    'server ideas decode video and tips; malformed and failed feeds fail',
    () async {
      final repository = IdeasRepository(
        url: 'https://fitness.example/ideas',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'items': [
                {
                  'name': 'Squat',
                  'category': 'strength',
                  'tips': 'Move smoothly',
                  'video_url': 'https://fitness.example/squat.mp4',
                },
              ],
            }),
            200,
          ),
        ),
      );
      final ideas = await repository.load();
      expect(ideas.single.video!.path, '/squat.mp4');
      expect(ideas.single.tips, 'Move smoothly');
      await expectLater(
        IdeasRepository(
          url: 'https://fitness.example/ideas',
          client: MockClient((_) async => http.Response('Unavailable', 503)),
        ).load(),
        throwsStateError,
      );
      expect(
        ExerciseIdea.fromJson({
          'name': 'Bad link',
          'video_url': 'javascript:bad',
        }).video,
        isNull,
      );
    },
  );

  Future<void> tap(WidgetTester tester, String text) async {
    const tabs = {
      'Previous sessions': 'Sessions',
      'Exercise ideas': 'Ideas',
      'Coach / Plan': 'Plan',
      'My profile': 'Profile',
    };
    final finder = find.text(tabs[text] ?? text);
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 200);
    }
    await tester.ensureVisible(finder.first);
    await tester.tap(finder.first);
    await tester.pumpAndSettle();
  }

  void viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('activity form retains entries when persistence fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExerciseEditor(
          onSave: (_) async => throw StateError('Disk unavailable'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, 'Squat');
    await tester.tap(find.text('Save exercise'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not save. Your entries are still here; please retry.'),
      findsOneWidget,
    );
    expect(find.text('Squat'), findsWidgets);
    expect(find.text('Save exercise'), findsOneWidget);
  });

  testWidgets(
    'dashboard starts a mixed session, resumes it, then shows completed history',
    (tester) async {
      viewport(tester);
      await tester.pumpWidget(MyApp(database: memory()));
      await tester.pumpAndSettle();
      for (final label in [
        'Start a new session',
        'Home',
        'Sessions',
        'Ideas',
        'Plan',
        'Profile',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tap(tester, 'Start a new session');
      await tap(tester, 'Add activity');
      await tester.enterText(find.byType(TextFormField).first, 'Squat');
      await tester.enterText(find.byType(TextFormField).at(1), '12');
      await tester.enterText(find.byType(TextFormField).at(2), '40');
      await tap(tester, 'Add set');
      await tester.enterText(find.byType(TextFormField).at(3), '8');
      await tap(tester, 'Save exercise');
      await tap(tester, 'Add activity');
      await tap(tester, 'Cardio');
      await tester.enterText(find.byType(TextFormField).first, 'Run');
      await tester.enterText(find.byType(TextFormField).at(1), '-1');
      await tester.enterText(find.byType(TextFormField).at(2), '140');
      await tap(tester, 'Save exercise');
      expect(find.text('Enter a number above 0, up to 1440'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(1), '20');
      await tap(tester, 'Save exercise');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, 'Resume active session');
      await tap(tester, 'Finish session');
      await tap(tester, 'Previous sessions');
      await tap(tester, 'Workout');
      expect(find.text('Set 1: 12 reps · 40 kg'), findsOneWidget);
      expect(find.text('Set 2: 8 reps · 40 kg'), findsOneWidget);
      expect(find.text('20 min · 140 BPM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('create a plan, use its target and save profile measurements', (
    tester,
  ) async {
    viewport(tester);
    await tester.pumpWidget(MyApp(database: memory()));
    await tester.pumpAndSettle();
    await tap(tester, 'Coach / Plan');
    await tap(tester, 'Create plan');
    await tap(tester, 'Add exercise');
    await tap(tester, 'Squat');
    await tap(tester, 'Save exercise');
    await tap(tester, 'Save plan');
    expect(find.text('Training plan'), findsOneWidget);
    await tap(tester, 'Home');
    await tester.pumpAndSettle();
    await tap(tester, 'Start a new session');
    await tap(tester, 'Training plan');
    expect(find.text('Plan · Training plan'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);
    expect(
      find.text(
        'Nothing logged yet. Choose a planned activity or add your own.',
      ),
      findsOneWidget,
    );
    await tap(tester, 'Squat');
    await tap(tester, 'Save exercise');
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tap(tester, 'Finish session');
    await tap(tester, 'Previous sessions');
    await tap(tester, 'Training plan');
    expect(find.text('Plan: Training plan'), findsOneWidget);
    expect(find.text('Planned: 1 sets · 10 reps'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, 'My profile');
    await tester.enterText(find.byType(TextField), 'Alex');
    await tap(tester, 'Save profile');
    await tap(tester, 'Add measurements');
    await tester.enterText(find.byType(TextFormField).first, '72.5');
    await tap(tester, 'Save measurements');
    expect(find.text('72.5'), findsOneWidget);
    expect(find.text('First measurement'), findsOneWidget);
    expect(find.text('Export my data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'small dashboard renders and exercise ideas report missing connection',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MyApp(database: memory()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tap(tester, 'My profile');
      await tester.enterText(find.byType(TextField), 'Draft name');
      await tap(tester, 'Home');
      await tap(tester, 'My profile');
      expect(find.text('Draft name'), findsOneWidget);
      await tap(tester, 'Exercise ideas');
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(
        find.text('Exercise ideas are not connected yet.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
