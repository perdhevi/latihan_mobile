import 'package:drift/drift.dart';

import '../features/sessions/session.dart';
import 'database.dart';
import 'fitness_api.dart';

class SyncException implements Exception {
  final String message;
  SyncException(this.message);
  @override
  String toString() => message;
}

/// The signed-in account is not the one this device last synced with.
class SyncAccountMismatch extends SyncException {
  SyncAccountMismatch()
    : super(
        'This device is synced with a different cloud account. Sign in with '
        'that account to continue.',
      );
}

class SyncReport {
  int pushed = 0;
  int pulled = 0;
  int removed = 0;
  int conflicts = 0;

  /// Items the server refused (validation, stale edit, still in use). They stay
  /// unsynced and are tried again on the next sync.
  final failures = <String>[];

  bool get changedLocal => pulled > 0 || removed > 0;
  String get summary =>
      'Sent $pushed, received $pulled, removed $removed'
      '${conflicts == 0 ? '' : ', resolved $conflicts conflicts'}'
      '${failures.isEmpty ? '' : '. ${failures.length} items need another try'}.';
}

enum _Action { none, push, pull }

class _Local {
  final String id;
  final DateTime updatedAt;

  /// Builds the write payload lazily: sessions need the plan links resolved
  /// after plans have synced.
  final Future<Map<String, dynamic>> Function() body;
  _Local(this.id, this.updatedAt, this.body);
}

abstract class _Kind {
  String get name;
  String get collection;
  Future<List<_Local>> locals();

  /// Writes the server record [remote] over the local row [localId], or as a
  /// new row with the server's ID when [localId] is null.
  Future<void> store(Map<String, dynamic> remote, String? localId);
  Future<void> removeLocal(String localId);
}

DateTime _parse(Object? iso) => DateTime.parse(iso as String).toUtc();

Map<String, dynamic> _planExercise(Exercise e) => e.isCardio
    ? {
        'name': e.name,
        'kind': 'cardio',
        'minutes': e.minutes,
        'avg_bpm': ?e.avgBpm,
      }
    : {
        'name': e.name,
        'kind': 'strength',
        'sets': [for (final s in e.sets) s.toJson()],
      };

/// Two-way synchronization with `fitness-api`, with the local database as the
/// source of truth.
///
/// The server issues every ID, so [SyncLinks] maps local rows to server
/// records. A sync is: profile, then plans, sessions and measurements (each:
/// push new and changed rows, pull new and changed records, apply deletions
/// seen on the server), then local deletions are sent. A row changed on both
/// sides keeps the more recently updated version.
///
/// It is safe to interrupt or repeat: creates carry an `Idempotency-Key`, and a
/// row is only marked synced after the server accepted it.
class SyncService {
  final AppDatabase db;
  final FitnessApi api;
  SyncService(this.db, this.api);

  final _report = SyncReport();
  final _plans = <String, Map<String, dynamic>>{};

  Future<SyncReport> sync() async {
    await _profile();
    await _run(_PlanKind(db, _plans));
    await _run(_SessionKind(db, _planLinks, _plans));
    await _run(_MeasurementKind(db));
    await _sendDeletes();
    return _report;
  }

  /// Forgets which account this device syncs with, so the next sync links it
  /// to whichever account is signed in. Local data is kept and will be
  /// uploaded to that account. With [eraseData] the device is emptied first,
  /// including any workout in progress and anything not yet synced.
  static Future<void> unlinkAccount(AppDatabase db, {bool eraseData = false}) =>
      db.transaction(() async {
        await db.delete(db.syncLinks).go();
        await db.delete(db.pendingDeletes).go();
        if (eraseData) {
          await db.delete(db.sessions).go();
          await db.delete(db.plans).go();
          await db.delete(db.measurements).go();
          await db.delete(db.profiles).go();
        }
      });

  // -- Links ---------------------------------------------------------------

  Future<List<SyncLinkRow>> _links(String kind) =>
      (db.select(db.syncLinks)..where((l) => l.kind.equals(kind))).get();

  Future<void> _link(
    String kind,
    String localId,
    Map<String, dynamic> remote,
    DateTime synced,
  ) => db
      .into(db.syncLinks)
      .insertOnConflictUpdate(
        SyncLinksCompanion.insert(
          kind: kind,
          localId: localId,
          remoteId: remote['id'] as String,
          remoteUpdatedAt: remote['updated_at'] as String,
          syncedUpdatedAt: synced,
        ),
      );

  Future<void> _unlink(String kind, String localId) => (db.delete(
    db.syncLinks,
  )..where((l) => l.kind.equals(kind) & l.localId.equals(localId))).go();

  /// The server ID of the plan a session refers to, whether the session named
  /// the plan by its local ID or (for sessions pulled from the server) by the
  /// server's.
  Future<String?> _planLinks(String planId) async {
    for (final link in await _links('plan')) {
      if (link.localId == planId || link.remoteId == planId) {
        return _plans.containsKey(link.remoteId) ? link.remoteId : null;
      }
    }
    return null;
  }

  // -- Profile -------------------------------------------------------------

  Future<void> _profile() async {
    final local = await db.select(db.profiles).getSingleOrNull();
    ApiResponse? remote;
    try {
      remote = await api.get('users/me');
    } on ApiException catch (e) {
      if (e.code != 'profile_required') rethrow;
    }
    if (remote == null) {
      if (local == null || local.displayName.trim().isEmpty) {
        throw SyncException(
          'Add your name under Profile first; a cloud account needs one.',
        );
      }
      final created = await api.post('users', {
        'display_name': local.displayName.trim(),
      }, idempotencyKey: 'profile');
      await _linkAccount(created.body['id'] as String);
      await _link('profile', '1', created.body, local.updatedAt);
      _report.pushed++;
      return;
    }
    await _linkAccount(remote.body['id'] as String);
    final updated = _parse(remote.body['updated_at']);
    final name = remote.body['display_name'] as String;
    if (local == null) {
      await _storeProfile(remote.body);
      _report.pulled++;
      return;
    }
    final link = (await _links('profile')).firstOrNull;
    final _Action action;
    if (link == null) {
      // First sync of an existing local profile.
      if (local.displayName == name) {
        await _link('profile', '1', remote.body, local.updatedAt);
        return;
      }
      _report.conflicts++;
      action = local.updatedAt.isAfter(updated) ? _Action.push : _Action.pull;
    } else {
      action = _decide(
        dirty: !local.updatedAt.isAtSameMomentAs(link.syncedUpdatedAt),
        changed: remote.body['updated_at'] != link.remoteUpdatedAt,
        local: local.updatedAt,
        remote: updated,
      );
    }
    switch (action) {
      case _Action.none:
        break;
      case _Action.push:
        final saved = await api.put('users/me', {
          'display_name': local.displayName.trim(),
        }, ifMatch: remote.etag);
        await _link('profile', '1', saved.body, local.updatedAt);
        _report.pushed++;
      case _Action.pull:
        await _storeProfile(remote.body);
        _report.pulled++;
    }
  }

  Future<void> _storeProfile(Map<String, dynamic> remote) async {
    final updated = _parse(remote['updated_at']);
    await db
        .into(db.profiles)
        .insertOnConflictUpdate(
          ProfilesCompanion.insert(
            id: const Value(1),
            displayName: remote['display_name'] as String,
            createdAt: _parse(remote['created_at']),
            updatedAt: updated,
          ),
        );
    await _link('profile', '1', remote, updated);
  }

  /// A device syncs with one account. Mixing two would upload one person's
  /// workouts into another's.
  Future<void> _linkAccount(String userId) async {
    final existing = (await _links('account')).firstOrNull;
    if (existing != null && existing.remoteId != userId) {
      throw SyncAccountMismatch();
    }
    if (existing == null) {
      await _link('account', 'self', {
        'id': userId,
        'updated_at': '',
      }, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    }
  }

  // -- Resources -----------------------------------------------------------

  _Action _decide({
    required bool dirty,
    required bool changed,
    required DateTime local,
    required DateTime remote,
  }) {
    if (!dirty && !changed) return _Action.none;
    if (dirty && !changed) return _Action.push;
    if (!dirty) return _Action.pull;
    _report.conflicts++;
    return local.isAfter(remote) ? _Action.push : _Action.pull;
  }

  /// Rejections of a single record, as opposed to a failed or unauthorised
  /// connection, which end the sync.
  bool _itemLevel(ApiException e) =>
      e.status >= 400 &&
      e.status < 500 &&
      e.status != 401 &&
      e.status != 408 &&
      e.status != 429;

  Future<void> _run(_Kind kind) async {
    final remote = {
      for (final item in await api.listAll(kind.collection))
        item['id'] as String: item,
    };
    if (kind is _PlanKind) _plans.addAll(remote);
    final remoteStore = kind is _PlanKind ? _plans : remote;
    final links = {for (final l in await _links(kind.name)) l.localId: l};
    final linkedRemote = {
      for (final l in links.values) l.remoteId,
      for (final l in await _links('retired:${kind.name}')) l.remoteId,
    };
    final pending = {
      for (final p in await (db.select(
        db.pendingDeletes,
      )..where((p) => p.kind.equals(kind.name))).get())
        p.remoteId,
    };

    Future<void> create(_Local local) async {
      final created = await api.post(
        kind.collection,
        await local.body(),
        idempotencyKey:
            '${kind.name}-${local.id}-${local.updatedAt.microsecondsSinceEpoch}',
      );
      remoteStore[created.body['id'] as String] = created.body;
      linkedRemote.add(created.body['id'] as String);
      await _link(kind.name, local.id, created.body, local.updatedAt);
      _report.pushed++;
    }

    for (final local in await kind.locals()) {
      final link = links[local.id];
      try {
        if (link == null) {
          await create(local);
          continue;
        }
        final current = remoteStore[link.remoteId];
        final dirty = !local.updatedAt.isAtSameMomentAs(link.syncedUpdatedAt);
        if (current == null) {
          // Deleted on the server. A local change since the last sync wins
          // and brings the record back; otherwise the deletion applies here.
          await _unlink(kind.name, local.id);
          linkedRemote.remove(link.remoteId);
          if (dirty) {
            await create(local);
          } else {
            await kind.removeLocal(local.id);
            _report.removed++;
          }
          continue;
        }
        final action = _decide(
          dirty: dirty,
          changed: current['updated_at'] != link.remoteUpdatedAt,
          local: local.updatedAt,
          remote: _parse(current['updated_at']),
        );
        switch (action) {
          case _Action.none:
            break;
          case _Action.push:
            final path = '${kind.collection}/${link.remoteId}';
            final etag = (await api.get(path)).etag;
            try {
              final saved = await api.put(
                path,
                await local.body(),
                ifMatch: etag,
              );
              remoteStore[link.remoteId] = saved.body;
              await _link(kind.name, local.id, saved.body, local.updatedAt);
              _report.pushed++;
            } on ApiException catch (e) {
              if (e.code != 'plan_in_use') rethrow;
              // Once sessions use a plan the server freezes its exercises. The
              // edited plan is uploaded as a new one; the old stays for those
              // sessions and is remembered so it is not pulled back as a copy.
              await _link('retired:${kind.name}', link.remoteId, {
                'id': link.remoteId,
                'updated_at': '',
              }, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
              await _unlink(kind.name, local.id);
              await create(local);
            }
          case _Action.pull:
            await kind.store(current, local.id);
            await _link(
              kind.name,
              local.id,
              current,
              _parse(current['updated_at']),
            );
            _report.pulled++;
        }
      } on ApiException catch (e) {
        if (!_itemLevel(e)) rethrow;
        _report.failures.add('${kind.name} ${local.id}: ${e.message}');
      }
    }

    // Records this device has not seen. Ones deleted here are removed from the
    // server below instead of coming back.
    for (final item in remote.values) {
      final id = item['id'] as String;
      if (linkedRemote.contains(id) || pending.contains(id)) continue;
      await kind.store(item, null);
      await _link(kind.name, id, item, _parse(item['updated_at']));
      _report.pulled++;
    }
  }

  Future<void> _sendDeletes() async {
    const collections = {
      'plan': 'plans',
      'session': 'sessions',
      'measurement': 'users/me/measurements',
    };
    for (final row in await db.select(db.pendingDeletes).get()) {
      try {
        await api.delete('${collections[row.kind]}/${row.remoteId}');
      } on ApiException catch (e) {
        // Already gone counts as deleted; "in use" (a plan some server session
        // still refers to) is retried later.
        if (e.status != 404) {
          if (!_itemLevel(e)) rethrow;
          _report.failures.add('${row.kind} ${row.remoteId}: ${e.message}');
          continue;
        }
      }
      await (db.delete(db.pendingDeletes)..where(
            (p) => p.kind.equals(row.kind) & p.remoteId.equals(row.remoteId),
          ))
          .go();
      _report.removed++;
    }
  }
}

class _PlanKind implements _Kind {
  final AppDatabase db;
  final Map<String, Map<String, dynamic>> cache;
  _PlanKind(this.db, this.cache);
  @override
  String get name => 'plan';
  @override
  String get collection => 'plans';

  @override
  Future<List<_Local>> locals() async => [
    for (final row in await db.select(db.plans).get())
      _Local(
        row.id,
        row.updatedAt,
        () async => {
          'name': row.name,
          'notes': row.notes,
          'exercises': [for (final e in row.exercises) _planExercise(e)],
        },
      ),
  ];

  @override
  Future<void> store(Map<String, dynamic> remote, String? localId) async {
    final plan = Plan.fromJson(remote);
    await db
        .into(db.plans)
        .insertOnConflictUpdate(
          PlansCompanion.insert(
            id: localId ?? plan.id,
            name: plan.name,
            notes: plan.notes,
            exercises: plan.exercises,
            createdAt: _parse(remote['created_at']),
            updatedAt: _parse(remote['updated_at']),
          ),
        );
  }

  @override
  Future<void> removeLocal(String localId) =>
      (db.delete(db.plans)..where((p) => p.id.equals(localId))).go();
}

class _SessionKind implements _Kind {
  final AppDatabase db;
  final Future<String?> Function(String planId) remotePlanId;
  final Map<String, Map<String, dynamic>> plans;
  _SessionKind(this.db, this.remotePlanId, this.plans);
  @override
  String get name => 'session';
  @override
  String get collection => 'sessions';

  @override
  Future<List<_Local>> locals() async => [
    // The session in progress is local only; the server holds completed ones.
    for (final row in await (db.select(
      db.sessions,
    )..where((s) => s.active.equals(false))).get())
      _Local(row.id, row.updatedAt, () => _body(row)),
  ];

  Future<Map<String, dynamic>> _body(SessionRow row) async {
    final snapshot = row.planSnapshot;
    final planId = snapshot == null ? null : await remotePlanId(snapshot.id);
    final remoteExercises = planId == null
        ? const []
        : plans[planId]!['exercises'] as List;

    // A logged exercise may name the plan entry it targeted. The server only
    // accepts entries of the plan as it is now, so find the same entry there
    // and otherwise leave the link out.
    String? link(String? entryId) {
      if (entryId == null || snapshot == null) return null;
      for (final r in remoteExercises) {
        if ((r as Map)['id'] == entryId) return entryId;
      }
      final index = snapshot.exercises.indexWhere((e) => e.id == entryId);
      if (index < 0 || index >= remoteExercises.length) return null;
      final candidate = remoteExercises[index] as Map;
      return candidate['name'] == snapshot.exercises[index].name
          ? candidate['id'] as String
          : null;
    }

    return {
      'name': row.name,
      'notes': row.notes,
      'performed_at': row.performedAt.toUtc().toIso8601String(),
      'plan_id': ?planId,
      'exercises': [
        for (final e in row.exercises)
          {..._planExercise(e), 'plan_exercise_id': ?link(e.planExerciseId)},
      ],
    };
  }

  @override
  Future<void> store(Map<String, dynamic> remote, String? localId) async {
    final session = WorkoutSession.fromJson(remote);
    await db
        .into(db.sessions)
        .insertOnConflictUpdate(
          SessionsCompanion.insert(
            id: localId ?? session.id,
            name: session.name,
            notes: session.notes,
            performedAt: session.date.toUtc(),
            exercises: session.exercises,
            planSnapshot: Value(session.plan),
            createdAt: _parse(remote['created_at']),
            updatedAt: _parse(remote['updated_at']),
          ),
        );
  }

  @override
  Future<void> removeLocal(String localId) =>
      (db.delete(db.sessions)..where((s) => s.id.equals(localId))).go();
}

class _MeasurementKind implements _Kind {
  final AppDatabase db;
  _MeasurementKind(this.db);
  @override
  String get name => 'measurement';
  @override
  String get collection => 'users/me/measurements';

  @override
  Future<List<_Local>> locals() async => [
    for (final row in await db.select(db.measurements).get())
      _Local(
        row.id,
        row.updatedAt,
        () async => {
          'measured_at': row.measuredAt.toUtc().toIso8601String(),
          'weight_kg': ?row.weightKg,
          'height_cm': ?row.heightCm,
          'body_fat_percent': ?row.bodyFatPercent,
          'waist_cm': ?row.waistCm,
          'chest_cm': ?row.chestCm,
          'hip_cm': ?row.hipCm,
        },
      ),
  ];

  @override
  Future<void> store(Map<String, dynamic> remote, String? localId) async {
    Value<double?> metric(String key) =>
        Value((remote[key] as num?)?.toDouble());
    await db
        .into(db.measurements)
        .insertOnConflictUpdate(
          MeasurementsCompanion.insert(
            id: localId ?? remote['id'] as String,
            measuredAt: _parse(remote['measured_at']),
            weightKg: metric('weight_kg'),
            heightCm: metric('height_cm'),
            bodyFatPercent: metric('body_fat_percent'),
            waistCm: metric('waist_cm'),
            chestCm: metric('chest_cm'),
            hipCm: metric('hip_cm'),
            createdAt: _parse(remote['created_at']),
            updatedAt: _parse(remote['updated_at']),
          ),
        );
  }

  @override
  Future<void> removeLocal(String localId) =>
      (db.delete(db.measurements)..where((m) => m.id.equals(localId))).go();
}
