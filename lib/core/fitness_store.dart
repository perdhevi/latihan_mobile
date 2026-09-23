import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/sessions/session.dart';

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String newId() => DateTime.now().microsecondsSinceEpoch.toString();

class FitnessStore extends ChangeNotifier {
  static const key = 'fitness_dashboard_v1';
  List<WorkoutSession> history = [];
  List<WorkoutSession> plans = [];
  WorkoutSession? active;
  List<Training> targets = [];
  String profileName = '';
  List<Map<String, dynamic>> measurements = [];
  bool loading = true;
  bool busy = false;
  String? error;

  Map<String, dynamic> encode() => {
    'history': history.map((s) => s.toJson()).toList(),
    'plans': plans.map((s) => s.toJson()).toList(),
    'active': active?.toJson(),
    'targets': targets.map((t) => t.toJson()).toList(),
    'profileName': profileName,
    'measurements': measurements,
  };
  void decode(Map<String, dynamic> data) {
    history =
        (data['history'] as List)
            .map((s) => WorkoutSession.fromJson(Map<String, dynamic>.from(s)))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    plans =
        (data['plans'] as List)
            .map((s) => WorkoutSession.fromJson(Map<String, dynamic>.from(s)))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    active = data['active'] == null
        ? null
        : WorkoutSession.fromJson(Map<String, dynamic>.from(data['active']));
    targets = (data['targets'] as List)
        .map((t) => Training.fromJson(Map<String, dynamic>.from(t)))
        .toList();
    profileName = data['profileName'] as String;
    measurements =
        (data['measurements'] as List)
            .map((m) => Map<String, dynamic>.from(m))
            .toList()
          ..sort(
            (a, b) => (b['date'] as String).compareTo(a['date'] as String),
          );
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) {
        history = await SessionRepository().load();
      } else {
        decode(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      error = 'Could not load your fitness data. Please retry.';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> change(void Function() update) async {
    if (busy) throw StateError('A save is already in progress');
    final before = jsonEncode(encode());
    busy = true;
    notifyListeners();
    try {
      update();
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(key, jsonEncode(encode()))) {
        throw StateError('Save failed');
      }
    } catch (_) {
      decode(jsonDecode(before) as Map<String, dynamic>);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> start() => change(() {
    if (active != null) return;
    final today = plans.where((p) => sameDay(p.date, DateTime.now())).toList();
    targets = today.expand((p) => p.trainings).toList();
    active = WorkoutSession(
      id: newId(),
      name: today.isEmpty ? 'Workout' : today.map((p) => p.name).join(' + '),
      date: DateTime.now(),
      trainings: [],
    );
  });
  Future<void> updateActive(String name, List<Training> trainings) =>
      change(() {
        final current = active!;
        active = WorkoutSession(
          id: current.id,
          name: name,
          date: current.date,
          trainings: trainings,
        );
      });
  Future<void> finish() => change(() {
    if (active == null || active!.trainings.isEmpty) {
      throw StateError('Log at least one activity');
    }
    history.insert(0, active!);
    active = null;
    targets = [];
  });
  Future<void> savePlan(WorkoutSession plan) => change(() {
    plans.removeWhere((p) => p.id == plan.id);
    plans.add(plan);
    plans.sort((a, b) => a.date.compareTo(b.date));
  });
}
