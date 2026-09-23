import 'package:flutter/material.dart';

import 'session.dart';
import 'sessions_screen.dart';

class SessionEditor extends StatefulWidget {
  final Future<void> Function(WorkoutSession) onSave;
  final bool planning;
  final WorkoutSession? initial;
  const SessionEditor({
    super.key,
    required this.onSave,
    this.planning = false,
    this.initial,
  });
  @override
  State<SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<SessionEditor> {
  final name = TextEditingController(text: 'Workout');
  final trainings = <Training>[];
  DateTime date = DateTime.now();
  bool saving = false;
  bool saved = false;
  String? error;
  @override
  void initState() {
    super.initState();
    name.text =
        widget.initial?.name ?? (widget.planning ? 'Training plan' : 'Workout');
    date = widget.initial?.date ?? DateTime.now();
    trainings.addAll(widget.initial?.trainings ?? []);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> addTraining({int? index}) async {
    final training = await Navigator.of(context).push<Training>(
      MaterialPageRoute(
        builder: (_) =>
            TrainingEditor(initial: index == null ? null : trainings[index]),
      ),
    );
    if (training != null && mounted) {
      setState(() {
        if (index == null) {
          trainings.add(training);
        } else {
          trainings[index] = training;
        }
        error = null;
      });
    }
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty || trainings.isEmpty) {
      setState(
        () => error = 'Enter a session name and add at least one exercise.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(
        WorkoutSession(
          id:
              widget.initial?.id ??
              DateTime.now().microsecondsSinceEpoch.toString(),
          name: name.text.trim(),
          date: date,
          trainings: List.of(trainings),
        ),
      );
      if (!mounted) return;
      setState(() {
        saved = true;
        saving = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not save. Your entries are still here; please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: saved,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || saving) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard this session?'),
          content: const Text('Unsaved training will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard == true && mounted) {
        setState(() => saved = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.planning ? 'Training plan' : 'New session'),
      ),
      body: AbsorbPointer(
        absorbing: saving,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Session name',
                border: OutlineInputBorder(),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Session date'),
              subtitle: Text(sessionDate(date)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: widget.planning
                      ? DateTime(DateTime.now().year + 5)
                      : DateTime.now(),
                );
                if (selected != null && mounted) {
                  setState(() => date = selected);
                }
              },
            ),
            for (var i = 0; i < trainings.length; i++)
              Card(
                child: ListTile(
                  title: Text(trainings[i].name),
                  subtitle: Text(trainings[i].summary),
                  onTap: () => addTraining(index: i),
                  trailing: IconButton(
                    tooltip: 'Remove exercise',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => trainings.removeAt(i)),
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => addTraining(),
              icon: const Icon(Icons.add),
              label: const Text('Add exercise'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving ? null : save,
              child: Text(
                saving
                    ? 'Saving…'
                    : widget.planning
                    ? 'Save plan'
                    : 'Save session',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class TrainingEditor extends StatefulWidget {
  final Training? initial;
  final Future<void> Function(Training)? onSave;
  const TrainingEditor({super.key, this.initial, this.onSave});
  @override
  State<TrainingEditor> createState() => _TrainingEditorState();
}

class _TrainingEditorState extends State<TrainingEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController minutes;
  late final TextEditingController distance;
  late final List<TextEditingController> reps;
  late bool cardio;
  bool saving = false;
  String? saveError;
  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    name = TextEditingController(text: initial?.name);
    minutes = TextEditingController(text: initial?.minutes?.toString());
    distance = TextEditingController(text: initial?.kilometers?.toString());
    cardio = initial?.isCardio ?? false;
    reps = (initial != null && initial.reps.isNotEmpty ? initial.reps : [10])
        .map((r) => TextEditingController(text: '$r'))
        .toList();
  }

  @override
  void dispose() {
    name.dispose();
    minutes.dispose();
    distance.dispose();
    for (final r in reps) {
      r.dispose();
    }
    super.dispose();
  }

  String? positive(
    String? value, {
    bool integer = false,
    bool allowZero = false,
  }) {
    final number = integer
        ? int.tryParse(value ?? '')
        : double.tryParse((value ?? '').replaceAll(',', '.'));
    if (number == null ||
        !number.isFinite ||
        (allowZero ? number < 0 : number <= 0)) {
      return allowZero
          ? 'Enter zero or a positive number'
          : integer
          ? 'Enter a positive whole number'
          : 'Enter a positive number';
    }
    return null;
  }

  double decimal(TextEditingController controller) =>
      double.parse(controller.text.replaceAll(',', '.'));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.initial == null ? 'Add exercise' : 'Edit exercise'),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: name,
            decoration: const InputDecoration(
              labelText: 'Exercise name',
              hintText: 'e.g. Bench press or Running',
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter an exercise name'
                : null,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final suggestion
                  in (cardio
                      ? ['Running', 'Cycling', 'Walking', 'Rowing']
                      : ['Bench Press', 'Squat', 'Deadlift', 'Push-up']))
                ActionChip(
                  label: Text(suggestion),
                  onPressed: () => name.text = suggestion,
                ),
            ],
          ),
          const SizedBox(height: 20),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Strength'),
                icon: Icon(Icons.fitness_center),
              ),
              ButtonSegment(
                value: true,
                label: Text('Cardio'),
                icon: Icon(Icons.directions_run),
              ),
            ],
            selected: {cardio},
            onSelectionChanged: (value) =>
                setState(() => cardio = value.single),
          ),
          const SizedBox(height: 16),
          if (cardio) ...[
            TextFormField(
              controller: minutes,
              decoration: const InputDecoration(
                labelText: 'Duration (minutes)',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) => positive(value),
            ),
            TextFormField(
              controller: distance,
              decoration: const InputDecoration(
                labelText: 'Distance (km)',
                helperText: 'Use 0 for stationary cardio.',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) => positive(value, allowZero: true),
            ),
          ] else ...[
            Text(
              '${reps.length} sets',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (var i = 0; i < reps.length; i++)
              Row(
                key: ObjectKey(reps[i]),
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: reps[i],
                      decoration: InputDecoration(
                        labelText: 'Set ${i + 1} reps',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) => positive(value, integer: true),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove set',
                    onPressed: reps.length == 1
                        ? null
                        : () => setState(() {
                            final removed = reps.removeAt(i);
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => removed.dispose(),
                            );
                          }),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            TextButton.icon(
              onPressed: () => setState(
                () => reps.add(TextEditingController(text: reps.last.text)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add set'),
            ),
          ],
          const SizedBox(height: 24),
          if (saveError != null)
            Text(
              saveError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    final training = Training(
                      name: name.text.trim(),
                      reps: cardio
                          ? []
                          : reps.map((r) => int.parse(r.text)).toList(),
                      minutes: cardio ? decimal(minutes) : null,
                      kilometers: cardio ? decimal(distance) : null,
                    );
                    setState(() {
                      saving = true;
                      saveError = null;
                    });
                    try {
                      await widget.onSave?.call(training);
                      if (context.mounted) Navigator.of(context).pop(training);
                    } catch (_) {
                      if (mounted) {
                        setState(() {
                          saving = false;
                          saveError = 'Could not save. Your entries are still here; please retry.';
                        });
                      }
                    }
                  },
            child: Text(saving ? 'Saving…' : 'Save exercise'),
          ),
        ],
      ),
    ),
  );
}
