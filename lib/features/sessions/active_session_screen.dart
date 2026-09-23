import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/fitness_store.dart';
import '../dashboard/dashboard_screen.dart';
import 'session.dart';
import 'session_editor.dart';
import 'sessions_screen.dart';

class ActiveSessionScreen extends StatelessWidget {
  const ActiveSessionScreen({super.key});
  Future<void> log(
    BuildContext context,
    FitnessStore store, {
    Training? target,
    int? index,
  }) async {
    await Navigator.of(context).push<Training>(
      MaterialPageRoute(
        builder: (_) => TrainingEditor(
          initial: index == null ? target : store.active!.trainings[index],
          onSave: (result) async {
            final activities = [...store.active!.trainings];
            if (index == null) {
              activities.add(result);
            } else {
              activities[index] = result;
            }
            await store.updateActive(store.active!.name, activities);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FitnessStore>();
    final active = store.active;
    if (active == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session')),
        body: const Center(child: Text('Session completed.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Active session')),
      body: AbsorbPointer(
        absorbing: store.busy,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('IN PROGRESS'),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        active.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      trailing: IconButton(
                        tooltip: 'Rename session',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          var draftName = active.name;
                          final name = await showDialog<String>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Session name'),
                              content: TextFormField(
                                initialValue: active.name,
                                onChanged: (value) => draftName = value,
                                autofocus: true,
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    if (draftName.trim().isNotEmpty) {
                                      Navigator.pop(context, draftName.trim());
                                    }
                                  },
                                  child: const Text('Save'),
                                ),
                              ],
                            ),
                          );
                          if (name != null && context.mounted) {
                            await attempt(
                              context,
                              () => store.updateActive(name, active.trainings),
                            );
                          }
                        },
                      ),
                    ),
                    Text(
                      'Started ${sessionDate(active.date)} at ${TimeOfDay.fromDateTime(active.date).format(context)}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${active.trainings.length} activities logged · Saved on this device',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text("Today's plan", style: Theme.of(context).textTheme.titleLarge),
            const Text('Targets are a guide. Log your actual results below.'),
            if (store.targets.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No plan for today. Add an activity to train freely.',
                ),
              ),
            for (final target in store.targets)
              Card(
                child: ListTile(
                  title: Text(target.name),
                  subtitle: Text(target.summary),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap: () => log(context, store, target: target),
                ),
              ),
            const SizedBox(height: 18),
            Text(
              'Logged activities',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (active.trainings.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nothing logged yet. Choose a planned activity or add your own.',
                ),
              ),
            for (var i = 0; i < active.trainings.length; i++)
              Card(
                child: ListTile(
                  leading: Icon(
                    active.trainings[i].isCardio
                        ? Icons.directions_run
                        : Icons.fitness_center,
                  ),
                  title: Text(active.trainings[i].name),
                  subtitle: Text(active.trainings[i].summary),
                  onTap: () => log(context, store, index: i),
                  trailing: IconButton(
                    tooltip: 'Remove activity',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => attempt(
                      context,
                      () => store.updateActive(
                        active.name,
                        [...active.trainings]..removeAt(i),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => log(context, store),
              icon: const Icon(Icons.add),
              label: const Text('Add activity'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: active.trainings.isEmpty || store.busy
                  ? null
                  : () async {
                      await attempt(context, () async {
                        await store.finish();
                        if (context.mounted) Navigator.pop(context);
                      });
                    },
              child: Text(store.busy ? 'Saving…' : 'Finish session'),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can leave and resume this session later.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
