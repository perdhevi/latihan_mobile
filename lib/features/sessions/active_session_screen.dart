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
    Exercise? target,
    int? index,
  }) async {
    await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(
        builder: (_) => ExerciseEditor(
          initial: index == null
              ? target?.logged()
              : store.active!.exercises[index],
          onSave: (result) async {
            final activities = [...store.active!.exercises];
            if (index == null) {
              activities.add(result);
            } else {
              activities[index] = result;
            }
            await store.updateActive(exercises: activities);
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
    final full = active.exercises.length >= 100;
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
                        tooltip: 'Edit name and notes',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          var draftName = active.name;
                          var draftNotes = active.notes;
                          final saved = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Session details'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextFormField(
                                    initialValue: active.name,
                                    onChanged: (value) => draftName = value,
                                    autofocus: true,
                                    maxLength: 200,
                                    decoration: const InputDecoration(
                                      labelText: 'Session name',
                                      counterText: '',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    initialValue: active.notes,
                                    onChanged: (value) => draftNotes = value,
                                    maxLength: 4000,
                                    minLines: 1,
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                      labelText: 'Notes (optional)',
                                      counterText: '',
                                    ),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    if (draftName.trim().isNotEmpty) {
                                      Navigator.pop(context, true);
                                    }
                                  },
                                  child: const Text('Save'),
                                ),
                              ],
                            ),
                          );
                          if (saved == true && context.mounted) {
                            await attempt(
                              context,
                              () => store.updateActive(
                                name: draftName.trim(),
                                notes: draftNotes.trim(),
                              ),
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
                      '${active.exercises.length} activities logged · Saved on this device',
                    ),
                    if (active.notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(active.notes),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              active.plan == null ? 'Plan' : 'Plan · ${active.plan!.name}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (active.plan == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No plan for this session. Add an activity to train freely.',
                ),
              )
            else
              const Text('Targets are a guide. Log your actual results below.'),
            for (final target in active.plan?.exercises ?? const <Exercise>[])
              () {
                // Each plan entry can be logged once; afterwards it opens the
                // logged result.
                final done = active.exercises.indexWhere(
                  (e) => e.planExerciseId == target.id,
                );
                return Card(
                  child: ListTile(
                    title: Text(target.name),
                    subtitle: Text(target.summary),
                    trailing: Icon(
                      done < 0 ? Icons.add_circle_outline : Icons.check_circle,
                    ),
                    onTap: done >= 0
                        ? () => log(context, store, index: done)
                        : full
                        ? null
                        : () => log(context, store, target: target),
                  ),
                );
              }(),
            const SizedBox(height: 18),
            Text(
              'Logged activities',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (active.exercises.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nothing logged yet. Choose a planned activity or add your own.',
                ),
              ),
            for (var i = 0; i < active.exercises.length; i++)
              Card(
                child: ListTile(
                  leading: Icon(
                    active.exercises[i].isCardio
                        ? Icons.directions_run
                        : Icons.fitness_center,
                  ),
                  title: Text(active.exercises[i].name),
                  subtitle: Text(active.exercises[i].summary),
                  onTap: () => log(context, store, index: i),
                  trailing: IconButton(
                    tooltip: 'Remove activity',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => attempt(
                      context,
                      () => store.updateActive(
                        exercises: [...active.exercises]..removeAt(i),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: full ? null : () => log(context, store),
              icon: const Icon(Icons.add),
              label: const Text('Add activity'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: active.exercises.isEmpty || store.busy
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
