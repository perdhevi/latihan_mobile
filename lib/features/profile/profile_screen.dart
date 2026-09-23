import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/fitness_store.dart';
import '../dashboard/dashboard_screen.dart';
import '../sessions/sessions_screen.dart';

const metricLabels = {
  'weight': 'Weight (kg)',
  'arm': 'Arm (cm)',
  'waist': 'Waist (cm)',
  'chest': 'Chest (cm)',
};

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController name;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(
      text: context.read<FitnessStore>().profileName,
    );
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FitnessStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(
            child: CircleAvatar(
              radius: 38,
              child: Icon(Icons.person_outline, size: 42),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Your name'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: store.busy
                ? null
                : () => attempt(context, () async {
                    await store.change(
                      () => store.profileName = name.text.trim(),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile saved')),
                      );
                    }
                  }),
            child: const Text('Save profile'),
          ),
          const SizedBox(height: 24),
          Text(
            'Your progress',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text(
            'Record your measurements over time. All values are entered by you.',
          ),
          const SizedBox(height: 12),
          if (store.measurements.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No measurements yet. Add your starting point.'),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final metric in metricLabels.entries)
                if (store.measurements.any((m) => m[metric.key] != null))
                  _progress(store, metric.key, metric.value),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: store.busy
                ? null
                : () => openScreen(context, const MeasurementEditor()),
            icon: const Icon(Icons.add),
            label: const Text('Add measurements'),
          ),
          const SizedBox(height: 24),
          Text(
            'Measurement history',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final m in store.measurements)
            Card(
              child: ListTile(
                title: Text(sessionDate(DateTime.parse(m['date'] as String))),
                subtitle: Text(
                  [
                    for (final metric in metricLabels.entries)
                      if (m[metric.key] != null)
                        '${metric.value}: ${m[metric.key]}',
                  ].join('\n'),
                ),
                trailing: IconButton(
                  tooltip: 'Delete measurement',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: store.busy
                      ? null
                      : () async {
                          final yes = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete measurement?'),
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
                          if (yes == true && context.mounted) {
                            await attempt(
                              context,
                              () => store.change(
                                () => store.measurements.removeWhere(
                                  (entry) => entry['id'] == m['id'],
                                ),
                              ),
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

  Widget _progress(FitnessStore store, String key, String label) {
    final values = store.measurements.where((m) => m[key] != null).toList();
    final latest = (values.first[key] as num).toDouble();
    final delta = latest - (values.last[key] as num).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            Text(
              latest.toStringAsFixed(1),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              values.length < 2
                  ? 'First measurement'
                  : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} since first entry',
            ),
          ],
        ),
      ),
    );
  }
}

class MeasurementEditor extends StatefulWidget {
  const MeasurementEditor({super.key});
  @override
  State<MeasurementEditor> createState() => _MeasurementEditorState();
}

class _MeasurementEditorState extends State<MeasurementEditor> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final key in metricLabels.keys) key: TextEditingController(),
  };
  DateTime date = DateTime.now();
  String? error;
  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FitnessStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('Add measurements')),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Measurement date'),
              subtitle: Text(sessionDate(date)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (picked != null && mounted) setState(() => date = picked);
              },
            ),
            for (final metric in metricLabels.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextFormField(
                  controller: fields[metric.key],
                  decoration: InputDecoration(
                    labelText: metric.value,
                    helperText: 'Optional',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final n = double.tryParse(value.replaceAll(',', '.'));
                    return n == null || !n.isFinite || n <= 0
                        ? 'Enter a positive number'
                        : null;
                  },
                ),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FilledButton(
              onPressed: store.busy
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      if (fields.values.every((c) => c.text.trim().isEmpty)) {
                        setState(
                          () => error = 'Enter at least one measurement.',
                        );
                        return;
                      }
                      await attempt(context, () async {
                        await store.change(() {
                          store.measurements.add({
                            'id': newId(),
                            'date': date.toIso8601String(),
                            for (final field in fields.entries)
                              if (field.value.text.trim().isNotEmpty)
                                field.key: double.parse(
                                  field.value.text.replaceAll(',', '.'),
                                ),
                          });
                          store.measurements.sort(
                            (a, b) => (b['date'] as String).compareTo(
                              a['date'] as String,
                            ),
                          );
                        });
                        if (context.mounted) Navigator.pop(context);
                      });
                    },
              child: Text(store.busy ? 'Saving…' : 'Save measurements'),
            ),
          ],
        ),
      ),
    );
  }
}
