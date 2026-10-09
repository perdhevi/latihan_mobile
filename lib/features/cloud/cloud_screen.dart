import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cloud_sync.dart';
import '../../core/fitness_api.dart';
import '../../core/fitness_store.dart';
import '../dashboard/dashboard_screen.dart';
import '../sessions/session.dart';

class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});
  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  late final cloud = context.read<CloudSync>();
  late final url = TextEditingController(
    text: cloud.url ?? const String.fromEnvironment('FITNESS_API_URL'),
  );
  final email = TextEditingController();
  final password = TextEditingController();
  late final name = TextEditingController(
    text: context.read<FitnessStore>().profileName,
  );
  bool busy = false;
  String? error;
  String? cursor;
  final items = <WorkoutSession>[];

  @override
  void initState() {
    super.initState();
    if (cloud.signedIn && !cloud.needsProfile) run(() => load());
  }

  @override
  void dispose() {
    for (final controller in [url, email, password, name]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (mounted) {
      setState(() {
        busy = true;
        error = null;
      });
    }
    try {
      await action();
    } catch (e) {
      if (mounted) {
        error = e is ApiException
            ? e.message
            : 'Could not connect. Check the server address and try again.';
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load({bool more = false}) async {
    final page = await cloud.api!.sessions(cursor: more ? cursor : null);
    final entries = (page['items'] as List)
        .map(
          (e) => WorkoutSession.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    if (!mounted) return;
    if (!more) items.clear();
    items.addAll(entries);
    cursor = page['next_cursor'] as String?;
  }

  /// true: erase this device first; false: keep its data and upload it to the
  /// new account; null: cancel.
  Future<bool?> askSwitchAccount() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Different account'),
      content: const Text(
        'This device was synced with another cloud account. Erase the data on '
        'this device and start from this account, or keep it and upload it to '
        'this account? Anything not yet synced is lost if you erase.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep and upload'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Erase this device'),
        ),
      ],
    ),
  );

  Future<void> syncNow() async {
    await cloud.sync(onAccountMismatch: askSwitchAccount);
    if (mounted && cloud.signedIn && !cloud.needsProfile) await load();
  }

  Future<void> connect(bool register) async {
    await cloud.signIn(url.text, email.text, password.text, register: register);
    password.clear();
    if (cloud.needsProfile) return;
    await syncNow();
  }

  String? status(CloudSync cloud) {
    final at = cloud.lastSyncAt;
    if (cloud.lastResult == null || at == null) return null;
    final time = TimeOfDay.fromDateTime(at).format(context);
    return 'Last synced $time. ${cloud.lastResult}';
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudSync>();
    final working = busy || cloud.syncing;
    final problem = error ?? cloud.problem;
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Your workouts are saved on this device first and work offline. '
            'When you are signed in they sync automatically when the app opens '
            'and shortly after you save changes.',
          ),
          const SizedBox(height: 20),
          if (!cloud.signedIn) ...[
            TextField(
              controller: url,
              enabled: !working,
              decoration: const InputDecoration(
                labelText: 'API URL (ending in /api/v1/)',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              enabled: !working,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              enabled: !working,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: working ? null : () => run(() => connect(false)),
              child: const Text('Sign in'),
            ),
            OutlinedButton(
              onPressed: working ? null : () => run(() => connect(true)),
              child: const Text('Create account'),
            ),
            const Text(
              'Built-in Go accounts. You stay signed in on this device until '
              'you sign out.',
            ),
          ] else ...[
            if (cloud.needsProfile) ...[
              TextField(
                controller: name,
                enabled: !working,
                decoration: const InputDecoration(
                  labelText: 'Cloud display name',
                ),
              ),
              FilledButton(
                onPressed: working
                    ? null
                    : () => run(() async {
                        await cloud.createProfile(name.text);
                        await syncNow();
                      }),
                child: const Text('Create cloud profile'),
              ),
            ] else ...[
              Text(
                cloud.displayName ?? 'Cloud workouts',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              FilledButton(
                onPressed: working ? null : () => run(syncNow),
                child: Text(
                  cloud.accountConflict ? 'Resolve account…' : 'Sync now',
                ),
              ),
              if (status(cloud) != null) Text(status(cloud)!),
              OutlinedButton(
                onPressed: working ? null : () => run(() => load()),
                child: const Text('Refresh cloud workouts'),
              ),
              if (items.isEmpty && !working)
                const Text('No cloud workouts yet.'),
              for (final session in items) sessionCard(context, session),
              if (cursor != null)
                TextButton(
                  onPressed: working ? null : () => run(() => load(more: true)),
                  child: const Text('Load more'),
                ),
            ],
            TextButton(
              onPressed: working
                  ? null
                  : () => run(() async {
                      try {
                        await cloud.signOut();
                      } finally {
                        items.clear();
                        cursor = null;
                      }
                    }),
              child: const Text('Sign out'),
            ),
            const Text('Signing out keeps your workouts on this device.'),
          ],
          if (working) const Center(child: CircularProgressIndicator()),
          if (problem != null)
            Text(
              problem,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
