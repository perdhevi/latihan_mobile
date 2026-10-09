import 'dart:math';

final _random = Random.secure();
int _lastMillis = 0;
int _sequence = 0;

/// A new UUID (v7): the first 48 bits are the creation time in milliseconds, so
/// IDs sort by creation and new rows append to the end of the index. Within one
/// millisecond a counter keeps IDs from this device increasing. The rest is
/// random.
String newId() {
  var millis = DateTime.now().millisecondsSinceEpoch;
  if (millis <= _lastMillis) {
    millis = _lastMillis;
    if (++_sequence > 0xfff) {
      // More than 4096 IDs in one millisecond: borrow the next one.
      millis++;
      _sequence = 0;
    }
  } else {
    _sequence = _random.nextInt(0x800); // headroom for the counter
  }
  _lastMillis = millis;
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  for (var i = 0; i < 6; i++) {
    bytes[i] = (millis >> (8 * (5 - i))) & 0xff;
  }
  bytes[6] = 0x70 | (_sequence >> 8);
  bytes[7] = _sequence & 0xff;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String formatNumber(double value) => value == value.truncateToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

// The models below use the API's JSON field names, so the same decoding serves
// local storage and server responses.

class ExerciseSet {
  final int repetitions;

  /// 0 means bodyweight.
  final double weightKg;
  const ExerciseSet(this.repetitions, [this.weightKg = 0]);
  Map<String, dynamic> toJson() => {
    'repetitions': repetitions,
    'weight_kg': weightKg,
  };
  factory ExerciseSet.fromJson(Map<String, dynamic> json) => ExerciseSet(
    json['repetitions'] as int,
    (json['weight_kg'] as num).toDouble(),
  );
  String get label => weightKg == 0
      ? '$repetitions reps'
      : '$repetitions reps · ${formatNumber(weightKg)} kg';
}

/// Strength exercises have [sets]; cardio exercises have [minutes] and an
/// optional [avgBpm]. Plan entries carry an [id]; session entries logged
/// against a plan entry carry its ID as [planExerciseId].
class Exercise {
  final String? id;
  final String? planExerciseId;
  final String name;
  final List<ExerciseSet> sets;
  final double? minutes;
  final int? avgBpm;
  bool get isCardio => minutes != null;
  Exercise({
    this.id,
    this.planExerciseId,
    required this.name,
    this.sets = const [],
    this.minutes,
    this.avgBpm,
  });
  Map<String, dynamic> toJson() => {
    'id': ?id,
    'plan_exercise_id': ?planExerciseId,
    'name': name,
    'kind': isCardio ? 'cardio' : 'strength',
    'sets': isCardio ? null : sets.map((s) => s.toJson()).toList(),
    'minutes': minutes,
    'avg_bpm': avgBpm,
  };
  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id'] as String?,
    planExerciseId: json['plan_exercise_id'] as String?,
    name: json['name'] as String,
    sets: [
      for (final s in json['sets'] as List? ?? const [])
        ExerciseSet.fromJson(Map<String, dynamic>.from(s as Map)),
    ],
    minutes: (json['minutes'] as num?)?.toDouble(),
    avgBpm: json['avg_bpm'] as int?,
  );

  Exercise withId(String id) => Exercise(
    id: id,
    name: name,
    sets: sets,
    minutes: minutes,
    avgBpm: avgBpm,
  );

  /// A session entry pre-filled with this plan entry's targets.
  Exercise logged() => Exercise(
    planExerciseId: id,
    name: name,
    sets: sets,
    minutes: minutes,
    avgBpm: avgBpm,
  );

  String get summary => isCardio
      ? '${formatNumber(minutes!)} min${avgBpm == null ? '' : ' · $avgBpm BPM'}'
      : '${sets.length} sets · ${sets.map((s) => s.label).join(', ')}';
}

List<Exercise> _exercises(Object? json) => [
  for (final e in json as List)
    Exercise.fromJson(Map<String, dynamic>.from(e as Map)),
];

/// A reusable set of target exercises.
class Plan {
  final String id;
  final String name;
  final String notes;
  final List<Exercise> exercises;
  Plan({
    required this.id,
    required this.name,
    this.notes = '',
    required this.exercises,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'notes': notes,
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };
  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
    id: json['id'] as String,
    name: json['name'] as String,
    notes: json['notes'] as String? ?? '',
    exercises: _exercises(json['exercises']),
  );
}

class WorkoutSession {
  final String id;
  final String name;
  final String notes;
  final DateTime date;
  final List<Exercise> exercises;

  /// The plan as it was when this session started; later plan edits do not
  /// change it.
  final Plan? plan;
  WorkoutSession({
    required this.id,
    required this.name,
    this.notes = '',
    required this.date,
    required this.exercises,
    this.plan,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'notes': notes,
    'performed_at': date.toUtc().toIso8601String(),
    'plan_id': plan?.id,
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'plan_snapshot': plan?.toJson(),
  };
  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
    id: json['id'] as String,
    name: json['name'] as String,
    notes: json['notes'] as String? ?? '',
    date: DateTime.parse(json['performed_at'] as String).toLocal(),
    exercises: _exercises(json['exercises']),
    plan: json['plan_snapshot'] == null
        ? null
        : Plan.fromJson(
            Map<String, dynamic>.from(json['plan_snapshot'] as Map),
          ),
  );
  WorkoutSession copyWith({
    String? name,
    String? notes,
    List<Exercise>? exercises,
  }) => WorkoutSession(
    id: id,
    name: name ?? this.name,
    notes: notes ?? this.notes,
    date: date,
    exercises: exercises ?? this.exercises,
    plan: plan,
  );
}
