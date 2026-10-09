import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../features/sessions/session.dart';

part 'database.g.dart';

// Like the API, a plan or session is replaced as a whole, so its exercises are
// stored with it as JSON rather than in tables of their own.

class ExercisesConverter extends TypeConverter<List<Exercise>, String> {
  const ExercisesConverter();
  @override
  List<Exercise> fromSql(String fromDb) => [
    for (final e in jsonDecode(fromDb) as List)
      Exercise.fromJson(e as Map<String, dynamic>),
  ];
  @override
  String toSql(List<Exercise> value) =>
      jsonEncode([for (final e in value) e.toJson()]);
}

class PlanConverter extends TypeConverter<Plan, String> {
  const PlanConverter();
  @override
  Plan fromSql(String fromDb) =>
      Plan.fromJson(jsonDecode(fromDb) as Map<String, dynamic>);
  @override
  String toSql(Plan value) => jsonEncode(value.toJson());
}

@DataClassName('ProfileRow')
class Profiles extends Table {
  /// Always 1: the device holds a single profile.
  IntColumn get id => integer()();
  TextColumn get displayName => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MeasurementRow')
class Measurements extends Table {
  TextColumn get id => text()();
  DateTimeColumn get measuredAt => dateTime()();
  RealColumn get weightKg => real().nullable()();
  RealColumn get heightCm => real().nullable()();
  RealColumn get bodyFatPercent => real().nullable()();
  RealColumn get waistCm => real().nullable()();
  RealColumn get chestCm => real().nullable()();
  RealColumn get hipCm => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PlanRow')
class Plans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get notes => text()();
  TextColumn get exercises => text().map(const ExercisesConverter())();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SessionRow')
class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get notes => text()();
  DateTimeColumn get performedAt => dateTime()();
  TextColumn get exercises => text().map(const ExercisesConverter())();
  TextColumn get planSnapshot => text()
      .map(NullAwareTypeConverter.wrap(const PlanConverter()))
      .nullable()();

  /// True for the session in progress; every other row is history.
  BoolColumn get active => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Maps a local row to the record the server issued for it (the server rejects
/// client IDs). [syncedUpdatedAt] is the local `updated_at` last in agreement
/// with the server, so a row is unsynced exactly when the two differ;
/// [remoteUpdatedAt] likewise detects changes made on the server. One row with
/// kind `account` records which cloud account this device is linked to.
@DataClassName('SyncLinkRow')
class SyncLinks extends Table {
  /// `profile`, `plan`, `session`, `measurement` or `account`.
  TextColumn get kind => text()();
  TextColumn get localId => text()();
  TextColumn get remoteId => text()();
  TextColumn get remoteUpdatedAt => text()();
  DateTimeColumn get syncedUpdatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {kind, localId};
}

/// Server records whose local row was deleted; removed on the next sync.
@DataClassName('PendingDeleteRow')
class PendingDeletes extends Table {
  TextColumn get kind => text()();
  TextColumn get remoteId => text()();
  @override
  Set<Column> get primaryKey => {kind, remoteId};
}

@DriftDatabase(
  tables: [Profiles, Measurements, Plans, Sessions, SyncLinks, PendingDeletes],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'latihan'));
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(syncLinks);
        await m.createTable(pendingDeletes);
      }
    },
  );

  /// Call in the same transaction that deletes a local row: if it was synced,
  /// queues the server record for deletion and forgets the link.
  Future<void> recordRemoteDelete(String kind, String localId) async {
    final link =
        await (select(syncLinks)
              ..where((l) => l.kind.equals(kind) & l.localId.equals(localId)))
            .getSingleOrNull();
    if (link == null) return;
    await into(pendingDeletes).insertOnConflictUpdate(
      PendingDeletesCompanion.insert(kind: kind, remoteId: link.remoteId),
    );
    await (delete(
      syncLinks,
    )..where((l) => l.kind.equals(kind) & l.localId.equals(localId))).go();
  }
}
