import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Training {
  final String name;
  final List<int> reps;
  final double? minutes;
  final double? kilometers;
  bool get isCardio => minutes != null;
  Training({
    required this.name,
    this.reps = const [],
    this.minutes,
    this.kilometers,
  });
  Map<String, dynamic> toJson() => {
    'name': name,
    'reps': reps,
    'minutes': minutes,
    'kilometers': kilometers,
  };
  factory Training.fromJson(Map<String, dynamic> json) => Training(
    name: json['name'] as String,
    reps: List<int>.from(json['reps'] as List),
    minutes: (json['minutes'] as num?)?.toDouble(),
    kilometers: (json['kilometers'] as num?)?.toDouble(),
  );
  String get summary => isCardio
      ? '$minutes min · $kilometers km'
      : '${reps.length} sets · ${reps.join(', ')} reps';
}

class WorkoutSession {
  final String id;
  final String name;
  final DateTime date;
  final List<Training> trainings;
  WorkoutSession({
    required this.id,
    required this.name,
    required this.date,
    required this.trainings,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'date': date.toIso8601String(),
    'trainings': trainings.map((t) => t.toJson()).toList(),
  };
  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
    id: json['id'] as String,
    name: json['name'] as String,
    date: DateTime.parse(json['date'] as String),
    trainings: (json['trainings'] as List)
        .map((t) => Training.fromJson(t as Map<String, dynamic>))
        .toList(),
  );
}

class SessionRepository {
  static const storageKey = 'workout_sessions_v1';
  Future<List<WorkoutSession>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(storageKey);
    if (data == null) return [];
    final sessions = (jsonDecode(data) as List)
        .map((s) => WorkoutSession.fromJson(s as Map<String, dynamic>))
        .toList();
    sessions.sort((a, b) => b.date.compareTo(a.date));
    return sessions;
  }

  Future<void> save(List<WorkoutSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final success = await prefs.setString(
      storageKey,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
    if (!success) throw StateError('Could not save sessions');
  }
}
