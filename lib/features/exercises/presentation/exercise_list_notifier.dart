import 'package:flutter/foundation.dart';

import '../domain/exercise.dart';
import '../domain/exercise_repository.dart';

class ExerciseListNotifier extends ChangeNotifier {
  final ExerciseRepository _repository;

  ExerciseListNotifier(this._repository);

  List<Exercise> _exercises = [];
  List<Exercise> get exercises => _exercises;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Future<void> loadExercises() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _exercises = await _repository.getExercises();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
