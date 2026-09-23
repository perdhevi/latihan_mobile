import 'package:flutter/material.dart';

import 'session.dart';

String sessionDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

class SessionDetailScreen extends StatelessWidget {
  final WorkoutSession session;
  const SessionDetailScreen({super.key, required this.session});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(session.name)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          sessionDate(session.date),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        for (final training in session.trainings)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    training.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (training.isCardio)
                    Text(training.summary)
                  else
                    for (var i = 0; i < training.reps.length; i++)
                      Text('Set ${i + 1}: ${training.reps[i]} reps'),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
