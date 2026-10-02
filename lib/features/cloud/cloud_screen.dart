import 'package:flutter/material.dart';

import '../../core/fitness_api.dart';

class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});
  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  final url = TextEditingController(
    text: const String.fromEnvironment('FITNESS_API_URL'),
  );
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  FitnessApi? api;
  bool busy = false;
  bool needsProfile = false;
  String? error;
  String? displayName;
  String? cursor;
  final items = <Map<String, dynamic>>[];

  @override
  void dispose() {
    for (final controller in [url, email, password, name]) {
      controller.dispose();
    }
    api?.close();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
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
    final page = await api!.sessions(cursor: more ? cursor : null);
    final entries = (page['items'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (!mounted) return;
    if (!more) items.clear();
    items.addAll(entries);
    cursor = page['next_cursor'] as String?;
  }

  Future<void> connect(bool register) async {
    api?.close();
    api = FitnessApi(url.text.trim());
    await api!.signIn(email.text, password.text, register: register);
    password.clear();
    try {
      final profile = await api!.profile();
      if (!mounted) return;
      displayName = profile['display_name'] as String;
      needsProfile = false;
    } on ApiException catch (e) {
      if (e.code != 'profile_required') rethrow;
      needsProfile = true;
      return;
    }
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cloud account')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Your local workouts stay on this device. View workouts saved to your Go account here.',
        ),
        const SizedBox(height: 20),
        if (api?.signedIn != true) ...[
          TextField(
            controller: url,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'API URL (ending in /api/v1/)',
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: email,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            enabled: !busy,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : () => run(() => connect(false)),
            child: const Text('Sign in'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => run(() => connect(true)),
            child: const Text('Create account'),
          ),
          const Text(
            'Built-in Go accounts. Sign in again after closing this screen.',
          ),
        ] else ...[
          if (needsProfile) ...[
            TextField(
              controller: name,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Cloud display name',
              ),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () => run(() async {
                      final profile = await api!.createProfile(name.text);
                      if (!mounted) return;
                      displayName = profile['display_name'] as String;
                      needsProfile = false;
                      await load();
                    }),
              child: const Text('Create cloud profile'),
            ),
          ] else ...[
            Text(
              displayName ?? 'Cloud workouts',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            OutlinedButton(
              onPressed: busy ? null : () => run(() => load()),
              child: const Text('Refresh cloud workouts'),
            ),
            if (items.isEmpty && !busy) const Text('No cloud workouts yet.'),
            for (final session in items)
              Card(
                child: ExpansionTile(
                  title: Text(session['name'] as String),
                  subtitle: Text(
                    DateTime.parse(session['performed_at'] as String)
                        .toLocal()
                        .toString(),
                  ),
                  children: [
                    for (final exercise in session['exercises'] as List)
                      ListTile(
                        title: Text(exercise['name'] as String),
                        subtitle: Text(
                          exercise['kind'] == 'cardio'
                              ? '${exercise['minutes']} min${exercise['avg_bpm'] == null ? '' : ' · ${exercise['avg_bpm']} BPM'}'
                              : (exercise['sets'] as List)
                                    .map(
                                      (s) =>
                                          '${s['repetitions']} reps${s['weight_kg'] == null ? '' : ' · ${s['weight_kg']} kg'}',
                                    )
                                    .join('\n'),
                        ),
                      ),
                  ],
                ),
              ),
            if (cursor != null)
              TextButton(
                onPressed: busy ? null : () => run(() => load(more: true)),
                child: const Text('Load more'),
              ),
          ],
          TextButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    try {
                      await api!.signOut();
                    } finally {
                      items.clear();
                      cursor = null;
                      displayName = null;
                      needsProfile = false;
                    }
                  }),
            child: const Text('Sign out'),
          ),
        ],
        if (busy) const Center(child: CircularProgressIndicator()),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}
