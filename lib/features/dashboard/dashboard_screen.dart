import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/fitness_store.dart';
import '../sessions/session.dart';
import '../sessions/sessions_screen.dart';
import '../sessions/active_session_screen.dart';

Future<void> attempt(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Please try again.')),
      );
    }
  }
}

void openScreen(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<FitnessStore>();
    final now = DateTime.now();
    final week = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final recent = store.history
        .where((s) => !s.date.isBefore(week) && !s.date.isAfter(now))
        .toList();
    final sets = recent
        .expand((s) => s.exercises)
        .fold<int>(0, (total, e) => total + e.sets.length);
    final minutes = recent
        .expand((s) => s.exercises)
        .fold<double>(0, (total, e) => total + (e.minutes ?? 0));
    return Scaffold(
      body: SafeArea(
        child: store.loading
            ? const Center(child: CircularProgressIndicator())
            : store.error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(store.error!),
                    TextButton(
                      onPressed: store.load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        'YOUR TRAINING, YOUR PACE',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        store.profileName.isEmpty
                            ? 'Welcome to FitTrack'
                            : 'Hi, ${store.profileName}',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('THIS WEEK · ${recent.length} sessions'),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 36,
                                runSpacing: 12,
                                children: [
                                  Text(
                                    '$sets\nSets logged',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  Text(
                                    '${minutes.toStringAsFixed(0)} min\nCardio logged',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: List.generate(7, (i) {
                                  final day = week.add(Duration(days: i));
                                  final done = recent.any(
                                    (s) => sameDay(s.date, day),
                                  );
                                  return Column(
                                    children: [
                                      Icon(
                                        done
                                            ? Icons.check_circle
                                            : Icons.circle_outlined,
                                        size: 22,
                                        color: done
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                            : Colors.grey,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: store.busy
                            ? null
                            : () async {
                                Plan? plan;
                                if (store.active == null &&
                                    store.plans.isNotEmpty) {
                                  final choice = await choosePlan(
                                    context,
                                    store.plans,
                                  );
                                  if (choice == null || !context.mounted) {
                                    return;
                                  }
                                  plan = choice.$1;
                                }
                                await attempt(context, () async {
                                  await store.start(plan);
                                  if (context.mounted) {
                                    openScreen(
                                      context,
                                      const ActiveSessionScreen(),
                                    );
                                  }
                                });
                              },
                        icon: const Icon(Icons.play_arrow),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            store.active == null
                                ? 'Start a new session'
                                : 'Resume active session',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Recent sessions',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (store.history.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'Your completed sessions will appear here.',
                          ),
                        ),
                      for (final session in store.history.take(3))
                        sessionCard(context, session),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Asks which plan to train against. Null means dismissed; `(null,)` means
/// no plan.
Future<(Plan?,)?> choosePlan(BuildContext context, List<Plan> plans) =>
    showDialog<(Plan?,)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Start from a plan?'),
        children: [
          for (final plan in plans)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, (plan,)),
              child: Text(plan.name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, (null,)),
            child: const Text('No plan, train freely'),
          ),
        ],
      ),
    );

Widget sessionCard(BuildContext context, WorkoutSession session) => Card(
  child: ListTile(
    contentPadding: const EdgeInsets.all(16),
    leading: const Icon(Icons.fitness_center, color: Color(0xFFFF8A65)),
    title: Text(session.name),
    subtitle: Text(
      '${sessionDate(session.date)} · ${session.exercises.length} activities',
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => openScreen(context, SessionDetailScreen(session: session)),
  ),
);

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<FitnessStore>().history;
    return Scaffold(
      appBar: AppBar(title: const Text('Previous sessions')),
      body: sessions.isEmpty
          ? const Center(child: Text('No completed sessions yet.'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                for (final session in sessions) sessionCard(context, session),
              ],
            ),
    );
  }
}
