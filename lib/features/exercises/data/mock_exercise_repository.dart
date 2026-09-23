import '../domain/exercise.dart';
import '../domain/exercise_repository.dart';

class MockExerciseRepository implements ExerciseRepository {
  @override
  Future<List<Exercise>> getExercises() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));
    return [
      Exercise(
        id: '1',
        name: 'Bench Press',
        description: 'Chest exercise',
        category: 'Strength',
        muscleGroup: 'Chest',
        equipment: 'Barbell',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      Exercise(
        id: '2',
        name: 'Squat',
        description: 'Leg exercise',
        category: 'Strength',
        muscleGroup: 'Legs',
        equipment: 'Barbell',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];
  }
}
