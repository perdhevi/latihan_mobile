import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/mock_exercise_repository.dart';
import 'exercise_list_notifier.dart';

class ExerciseListScreen extends StatelessWidget {
  const ExerciseListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          ExerciseListNotifier(MockExerciseRepository())..loadExercises(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Exercise Library')),
        body: Consumer<ExerciseListNotifier>(
          builder: (context, notifier, child) {
            if (notifier.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (notifier.error != null) {
              return Center(child: Text('Error: ${notifier.error}'));
            }
            if (notifier.exercises.isEmpty) {
              return const Center(child: Text('No exercises found.'));
            }
            return ListView.builder(
              itemCount: notifier.exercises.length,
              itemBuilder: (context, index) {
                final exercise = notifier.exercises[index];
                return ListTile(
                  title: Text(exercise.name),
                  subtitle: Text(exercise.muscleGroup),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
