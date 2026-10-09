import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../features/sessions/session.dart';
import 'database.dart';

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _time(DateTime time) => time.toUtc().toIso8601String();

WorkoutSession _session(SessionRow row) => WorkoutSession(
  id: row.id,
  name: row.name,
  notes: row.notes,
  date: row.performedAt.toLocal(),
  exercises: row.exercises,
  plan: row.planSnapshot,
);

Plan _plan(PlanRow row) => Plan(
  id: row.id,
  name: row.name,
  notes: row.notes,
  exercises: row.exercises,
);

Map<String, dynamic> _measurement(MeasurementRow row) => {
  'id': row.id,
  'measured_at': _time(row.measuredAt),
  'weight_kg': ?row.weightKg,
  'height_cm': ?row.heightCm,
  'body_fat_percent': ?row.bodyFatPercent,
  'waist_cm': ?row.waistCm,
  'chest_cm': ?row.chestCm,
  'hip_cm': ?row.hipCm,
};

/// Holds the device's data in memory for the screens; every change is written
/// to [db] first.
class FitnessStore extends ChangeNotifier {
  final AppDatabase db;
  FitnessStore([AppDatabase? db]) : db = db ?? AppDatabase();

  List<WorkoutSession> history = [];
  List<Plan> plans = [];
  WorkoutSession? active;
  String profileName = '';

  /// Keyed like the API's Measurement: `id`, `measured_at` and the metrics.
  List<Map<String, dynamic>> measurements = [];
  bool loading = true;
  bool busy = false;
  String? error;

  /// Called after a change that synchronization should send (not after every
  /// edit to the session in progress, which is never synced).
  VoidCallback? onDataChanged;

  @override
  void dispose() {
    db.close();
    super.dispose();
  }

  Future<List<SessionRow>> _sessionRows() => (db.select(
    db.sessions,
  )..orderBy([(s) => OrderingTerm.desc(s.performedAt)])).get();
  Future<List<PlanRow>> _planRows() => (db.select(
    db.plans,
  )..orderBy([(p) => OrderingTerm.desc(p.createdAt)])).get();
  Future<List<MeasurementRow>> _measurementRows() => (db.select(
    db.measurements,
  )..orderBy([(m) => OrderingTerm.desc(m.measuredAt)])).get();

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final sessions = await _sessionRows();
      history = [
        for (final row in sessions)
          if (!row.active) _session(row),
      ];
      active = sessions.where((row) => row.active).map(_session).firstOrNull;
      plans = (await _planRows()).map(_plan).toList();
      measurements = (await _measurementRows()).map(_measurement).toList();
      final profile = await db.select(db.profiles).getSingleOrNull();
      profileName = profile?.displayName ?? '';
    } catch (_) {
      error = 'Could not load your fitness data. Please retry.';
    }
    loading = false;
    notifyListeners();
  }

  /// Runs [persist] and, only if it succeeds, [apply]s the same change to the
  /// in-memory state. A successful write that [synced] covers then calls
  /// [onDataChanged].
  Future<void> _write(
    Future<void> Function() persist,
    void Function() apply, {
    bool synced = true,
  }) async {
    if (busy) throw StateError('A save is already in progress');
    busy = true;
    notifyListeners();
    try {
      await persist();
      apply();
    } finally {
      busy = false;
      notifyListeners();
    }
    if (synced) onDataChanged?.call();
  }

  Future<void> _putSession(WorkoutSession session, {required bool active}) {
    final now = DateTime.now().toUtc();
    final row = SessionsCompanion.insert(
      id: session.id,
      name: session.name,
      notes: session.notes,
      performedAt: session.date.toUtc(),
      exercises: session.exercises,
      planSnapshot: Value(session.plan),
      active: Value(active),
      createdAt: now,
      updatedAt: now,
    );
    return db
        .into(db.sessions)
        .insert(
          row,
          onConflict: DoUpdate(
            (_) => row.copyWith(createdAt: const Value.absent()),
          ),
        );
  }

  /// Starts a session, optionally against [plan], whose current exercises
  /// become the session's targets.
  Future<void> start([Plan? plan]) async {
    if (active != null) return;
    final session = WorkoutSession(
      id: newId(),
      name: plan?.name ?? 'Workout',
      date: DateTime.now(),
      exercises: [],
      plan: plan,
    );
    await _write(
      () => _putSession(session, active: true),
      () => active = session,
      synced: false,
    );
  }

  Future<void> updateActive({
    String? name,
    String? notes,
    List<Exercise>? exercises,
  }) {
    final session = active!.copyWith(
      name: name,
      notes: notes,
      exercises: exercises,
    );
    return _write(
      () => _putSession(session, active: true),
      () => active = session,
      synced: false,
    );
  }

  Future<void> finish() async {
    final session = active;
    if (session == null || session.exercises.isEmpty) {
      throw StateError('Log at least one activity');
    }
    await _write(() => _putSession(session, active: false), () {
      history.insert(0, session);
      active = null;
    });
  }

  Future<void> savePlan(Plan plan) {
    // As in the API, every write issues new exercise entry IDs; sessions keep
    // the snapshot they started with.
    final saved = Plan(
      id: plan.id,
      name: plan.name,
      notes: plan.notes,
      exercises: [for (final e in plan.exercises) e.withId(newId())],
    );
    final now = DateTime.now().toUtc();
    final row = PlansCompanion.insert(
      id: saved.id,
      name: saved.name,
      notes: saved.notes,
      exercises: saved.exercises,
      createdAt: now,
      updatedAt: now,
    );
    return _write(
      () => db
          .into(db.plans)
          .insert(
            row,
            onConflict: DoUpdate(
              (_) => row.copyWith(createdAt: const Value.absent()),
            ),
          ),
      () {
        final index = plans.indexWhere((p) => p.id == plan.id);
        if (index < 0) {
          plans.insert(0, saved);
        } else {
          plans[index] = saved;
        }
      },
    );
  }

  Future<void> deletePlan(String id) => _write(
    () => db.transaction(() async {
      await db.recordRemoteDelete('plan', id);
      await (db.delete(db.plans)..where((p) => p.id.equals(id))).go();
    }),
    () => plans.removeWhere((p) => p.id == id),
  );

  Future<void> saveProfileName(String name) {
    final now = DateTime.now().toUtc();
    final row = ProfilesCompanion.insert(
      id: const Value(1),
      displayName: name,
      createdAt: now,
      updatedAt: now,
    );
    return _write(
      () => db
          .into(db.profiles)
          .insert(
            row,
            onConflict: DoUpdate(
              (_) => row.copyWith(createdAt: const Value.absent()),
            ),
          ),
      () => profileName = name,
    );
  }

  /// [measurement] holds `measured_at` and at least one metric.
  Future<void> addMeasurement(Map<String, dynamic> measurement) {
    Value<double?> metric(String key) =>
        Value((measurement[key] as num?)?.toDouble());
    final now = DateTime.now().toUtc();
    final saved = {'id': newId(), ...measurement};
    return _write(
      () => db
          .into(db.measurements)
          .insert(
            MeasurementsCompanion.insert(
              id: saved['id'] as String,
              measuredAt: DateTime.parse(saved['measured_at'] as String),
              weightKg: metric('weight_kg'),
              heightCm: metric('height_cm'),
              bodyFatPercent: metric('body_fat_percent'),
              waistCm: metric('waist_cm'),
              chestCm: metric('chest_cm'),
              hipCm: metric('hip_cm'),
              createdAt: now,
              updatedAt: now,
            ),
          ),
      () => measurements
        ..add(saved)
        ..sort(
          (a, b) =>
              DateTime.parse(b['measured_at'] as String)
                  .compareTo(DateTime.parse(a['measured_at'] as String)),
        ),
    );
  }

  Future<void> deleteMeasurement(String id) => _write(
    () => db.transaction(() async {
      await db.recordRemoteDelete('measurement', id);
      await (db.delete(db.measurements)..where((m) => m.id.equals(id))).go();
    }),
    () => measurements.removeWhere((m) => m['id'] == id),
  );

  /// Everything stored on this device as one JSON document, laid out like the
  /// API's account export.
  Future<Map<String, dynamic>> export() async {
    final profile = await db.select(db.profiles).getSingleOrNull();
    final sessions = [
      for (final row in await _sessionRows())
        (
          active: row.active,
          json: {
            ..._session(row).toJson(),
            'created_at': _time(row.createdAt),
            'updated_at': _time(row.updatedAt),
          },
        ),
    ];
    return {
      'format': 'latihan-mobile-export/1',
      'exported_at': _time(DateTime.now()),
      'user': profile == null
          ? null
          : {
              'display_name': profile.displayName,
              'created_at': _time(profile.createdAt),
              'updated_at': _time(profile.updatedAt),
            },
      'measurements': [
        for (final row in await _measurementRows())
          {
            ..._measurement(row),
            'created_at': _time(row.createdAt),
            'updated_at': _time(row.updatedAt),
          },
      ],
      'plans': [
        for (final row in await _planRows())
          {
            ..._plan(row).toJson(),
            'created_at': _time(row.createdAt),
            'updated_at': _time(row.updatedAt),
          },
      ],
      'sessions': [
        for (final s in sessions)
          if (!s.active) s.json,
      ],
      'active_session': sessions
          .where((s) => s.active)
          .map((s) => s.json)
          .firstOrNull,
    };
  }
}
