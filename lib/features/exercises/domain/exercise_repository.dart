import '../domain/exercise.dart';

abstract interface class ExerciseRepository {
  Future<List<Exercise>> getExercises();
}
