import 'package:flutter/material.dart';

import 'session.dart';

String sessionDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

class SessionDetailScreen extends StatelessWidget {
  final WorkoutSession session;
  const SessionDetailScreen({super.key, required this.session});
  @override
  Widget build(BuildContext context) {
    final titleMedium = Theme.of(context).textTheme.titleMedium;
    final planned = {
      for (final e in session.plan?.exercises ?? const <Exercise>[]) e.id: e,
    };
    final logged = {for (final e in session.exercises) e.planExerciseId};
    final missed = planned.values.where((e) => !logged.contains(e.id));
    return Scaffold(
      appBar: AppBar(title: Text(session.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(sessionDate(session.date), style: titleMedium),
          if (session.plan != null) Text('Plan: ${session.plan!.name}'),
          if (session.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(session.notes),
            ),
          const SizedBox(height: 16),
          for (final exercise in session.exercises)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exercise.name, style: titleMedium),
                    const SizedBox(height: 8),
                    if (exercise.isCardio)
                      Text(exercise.summary)
                    else
                      for (var i = 0; i < exercise.sets.length; i++)
                        Text('Set ${i + 1}: ${exercise.sets[i].label}'),
                    if (planned[exercise.planExerciseId] case final target?)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Planned: ${target.summary}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (missed.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Planned but not logged', style: titleMedium),
            for (final target in missed)
              Card(
                child: ListTile(
                  title: Text(target.name),
                  subtitle: Text(target.summary),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
