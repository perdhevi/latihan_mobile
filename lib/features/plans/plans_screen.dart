import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/fitness_store.dart';
import '../dashboard/dashboard_screen.dart';
import '../sessions/session.dart';
import '../sessions/session_editor.dart';

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<FitnessStore>();
    void edit([Plan? plan]) =>
        openScreen(context, PlanEditor(initial: plan, onSave: store.savePlan));
    return Scaffold(
      appBar: AppBar(title: const Text('Coach / Plan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: store.busy ? null : () => edit(),
        icon: const Icon(Icons.add),
        label: const Text('Create plan'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          Text(
            'Make a plan. Show up for yourself.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Build reusable plans with target sets, reps, weights or cardio minutes. Pick one when you start a session.',
          ),
          const SizedBox(height: 20),
          if (store.plans.isEmpty)
            const Text('No plans yet. Create your first training plan.'),
          for (final plan in store.plans)
            Card(
              child: ListTile(
                title: Text(plan.name),
                subtitle: Text(
                  '${plan.exercises.length} activities\n${plan.exercises.map((e) => e.name).join(', ')}',
                ),
                isThreeLine: true,
                onTap: () => edit(plan),
                trailing: IconButton(
                  tooltip: 'Delete plan',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: store.busy
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete this plan?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && context.mounted) {
                            await attempt(
                              context,
                              () => store.deletePlan(plan.id),
                            );
                          }
                        },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
