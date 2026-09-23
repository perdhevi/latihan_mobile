import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latihan_mobile/main.dart';
import 'package:latihan_mobile/features/sessions/session_editor.dart';
import 'package:latihan_mobile/core/fitness_store.dart';
import 'package:latihan_mobile/features/sessions/session.dart';
import 'package:latihan_mobile/features/ideas/ideas_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('legacy history migrates; plan targets and active results persist separately', () async {
    final previous = WorkoutSession(
      id: 'old',
      name: 'Old workout',
      date: DateTime(2026, 1, 1),
      trainings: [
        Training(name: 'Squat', reps: [12, 8]),
      ],
    );
    await SessionRepository().save([previous]);
    final store = FitnessStore();
    await store.load();
    expect(store.history.single.id, 'old');
    await store.savePlan(
      WorkoutSession(
        id: 'plan',
        name: 'Today plan',
        date: DateTime.now(),
        trainings: [Training(name: 'Run', minutes: 20, kilometers: 3)],
      ),
    );
    await store.start();
    expect(store.active!.trainings, isEmpty);
    expect(store.targets.single.name, 'Run');
    await store.updateActive('Morning', [
      Training(name: 'Run', minutes: 22, kilometers: 3.2),
    ]);
    final restored = FitnessStore();
    await restored.load();
    expect(restored.active!.name, 'Morning');
    expect(restored.active!.trainings.single.minutes, 22);
    expect(restored.targets.single.minutes, 20);
    expect(restored.history.length, 1);
    await restored.finish();
    final finished = FitnessStore();
    await finished.load();
    expect(finished.active, isNull);
    expect(finished.history.length, 2);
    expect(finished.plans.single.id, 'plan');
    expect(finished.targets, isEmpty);
  });

  test('empty sessions cannot finish; measurements survive reload', () async {
    final store = FitnessStore();
    await store.load();
    await store.start();
    await expectLater(store.finish(), throwsStateError);
    expect(store.active, isNotNull);
    await store.change(() {
      store.profileName = 'Alex';
      store.measurements.add({
        'id': '1',
        'date': DateTime.now().toIso8601String(),
        'weight': 72.5,
        'arm': 32.0,
      });
    });
    final restored = FitnessStore();
    await restored.load();
    expect(restored.profileName, 'Alex');
    expect(restored.measurements.single['weight'], 72.5);
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
        home: TrainingEditor(
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
      await tester.pumpWidget(const MyApp());
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
      await tester.enterText(find.byType(TextFormField).last, '12');
      await tap(tester, 'Add set');
      await tester.enterText(find.byType(TextFormField).last, '8');
      await tap(tester, 'Save exercise');
      await tap(tester, 'Add activity');
      await tap(tester, 'Cardio');
      await tester.enterText(find.byType(TextFormField).first, 'Run');
      await tester.enterText(find.byType(TextFormField).at(1), '-1');
      await tester.enterText(find.byType(TextFormField).at(2), '3.2');
      await tap(tester, 'Save exercise');
      expect(find.text('Enter a positive number'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(1), '20');
      await tap(tester, 'Save exercise');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, 'Resume active session');
      await tap(tester, 'Finish session');
      await tap(tester, 'Previous sessions');
      await tap(tester, 'Workout');
      expect(find.text('Set 1: 12 reps'), findsOneWidget);
      expect(find.text('Set 2: 8 reps'), findsOneWidget);
      expect(find.text('20.0 min · 3.2 km'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('create a plan, use its target and save profile measurements', (
    tester,
  ) async {
    viewport(tester);
    await tester.pumpWidget(const MyApp());
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
    expect(find.text('Squat'), findsOneWidget);
    expect(
      find.text(
        'Nothing logged yet. Choose a planned activity or add your own.',
      ),
      findsOneWidget,
    );
    await tap(tester, 'Squat');
    await tap(tester, 'Save exercise');
    await tap(tester, 'Finish session');
    await tap(tester, 'My profile');
    await tester.enterText(find.byType(TextField), 'Alex');
    await tap(tester, 'Save profile');
    await tap(tester, 'Add measurements');
    await tester.enterText(find.byType(TextFormField).first, '72.5');
    await tap(tester, 'Save measurements');
    expect(find.text('72.5'), findsOneWidget);
    expect(find.text('First measurement'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'small dashboard renders and exercise ideas report missing connection',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MyApp());
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
