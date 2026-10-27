import 'package:flutter/material.dart';

import 'session.dart';

/// Validates a number against the API's bounds. [above] excludes [min] itself.
String? numberError(
  String? value,
  num min,
  num max, {
  bool integer = false,
  bool above = false,
  bool optional = false,
}) {
  final text = (value ?? '').trim();
  if (optional && text.isEmpty) return null;
  final number = integer
      ? int.tryParse(text)
      : double.tryParse(text.replaceAll(',', '.'));
  if (number == null ||
      !number.isFinite ||
      number > max ||
      (above ? number <= min : number < min)) {
    return 'Enter a ${integer ? 'whole ' : ''}number '
        '${above ? 'above $min, up to' : 'from $min to'} $max';
  }
  return null;
}

class PlanEditor extends StatefulWidget {
  final Future<void> Function(Plan) onSave;
  final Plan? initial;
  const PlanEditor({super.key, required this.onSave, this.initial});
  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  late final name = TextEditingController(
    text: widget.initial?.name ?? 'Training plan',
  );
  late final notes = TextEditingController(text: widget.initial?.notes);
  late final exercises = [...?widget.initial?.exercises];
  bool saving = false;
  bool saved = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> editExercise({int? index}) async {
    final exercise = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(
        builder: (_) =>
            ExerciseEditor(initial: index == null ? null : exercises[index]),
      ),
    );
    if (exercise != null && mounted) {
      setState(() {
        if (index == null) {
          exercises.add(exercise);
        } else {
          exercises[index] = exercise;
        }
        error = null;
      });
    }
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty || exercises.isEmpty) {
      setState(
        () => error = 'Enter a plan name and add at least one exercise.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(
        Plan(
          id: widget.initial?.id ?? newId(),
          name: name.text.trim(),
          notes: notes.text.trim(),
          exercises: List.of(exercises),
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
          title: const Text('Discard this plan?'),
          content: const Text('Unsaved changes will be lost.'),
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
      appBar: AppBar(title: const Text('Training plan')),
      body: AbsorbPointer(
        absorbing: saving,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: name,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Plan name',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              maxLength: 4000,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < exercises.length; i++)
              Card(
                child: ListTile(
                  title: Text(exercises[i].name),
                  subtitle: Text(exercises[i].summary),
                  onTap: () => editExercise(index: i),
                  trailing: IconButton(
                    tooltip: 'Remove exercise',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => exercises.removeAt(i)),
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: exercises.length >= 100 ? null : () => editExercise(),
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
              child: Text(saving ? 'Saving…' : 'Save plan'),
            ),
          ],
        ),
      ),
    ),
  );
}

typedef _SetFields = ({
  TextEditingController reps,
  TextEditingController weight,
});

class ExerciseEditor extends StatefulWidget {
  final Exercise? initial;
  final Future<void> Function(Exercise)? onSave;
  const ExerciseEditor({super.key, this.initial, this.onSave});
  @override
  State<ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends State<ExerciseEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController minutes;
  late final TextEditingController bpm;
  late final List<_SetFields> sets;
  late bool cardio;
  bool saving = false;
  String? saveError;

  _SetFields fields(String reps, String weight) => (
    reps: TextEditingController(text: reps),
    weight: TextEditingController(text: weight),
  );

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    name = TextEditingController(text: initial?.name);
    minutes = TextEditingController(
      text: initial?.minutes == null ? null : formatNumber(initial!.minutes!),
    );
    bpm = TextEditingController(text: initial?.avgBpm?.toString());
    cardio = initial?.isTimed ?? false;
    sets = [
      for (final s in initial?.sets ?? const <ExerciseSet>[])
        fields('${s.repetitions}', formatNumber(s.weightKg)),
    ];
    if (sets.isEmpty) sets.add(fields('10', '0'));
  }

  @override
  void dispose() {
    name.dispose();
    minutes.dispose();
    bpm.dispose();
    for (final s in sets) {
      s.reps.dispose();
      s.weight.dispose();
    }
    super.dispose();
  }

  double decimal(TextEditingController controller) =>
      double.parse(controller.text.trim().replaceAll(',', '.'));
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
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Exercise name',
              hintText: 'e.g. Bench press or Running',
              counterText: '',
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
              validator: (value) => numberError(value, 0, 1440, above: true),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: bpm,
              decoration: const InputDecoration(
                labelText: 'Average heart rate (BPM)',
                helperText: 'Optional',
              ),
              keyboardType: TextInputType.number,
              validator: (value) =>
                  numberError(value, 1, 300, integer: true, optional: true),
            ),
          ] else ...[
            Text(
              '${sets.length} sets',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text('Use 0 kg for bodyweight.'),
            const SizedBox(height: 8),
            for (var i = 0; i < sets.length; i++)
              Padding(
                key: ObjectKey(sets[i].reps),
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: sets[i].reps,
                        decoration: InputDecoration(
                          labelText: 'Set ${i + 1} reps',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) =>
                            numberError(value, 1, 1000, integer: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: sets[i].weight,
                        decoration: const InputDecoration(
                          labelText: 'Weight (kg)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) => numberError(value, 0, 2000),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove set',
                      onPressed: sets.length == 1
                          ? null
                          : () => setState(() {
                              final removed = sets.removeAt(i);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                removed.reps.dispose();
                                removed.weight.dispose();
                              });
                            }),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: sets.length >= 100
                  ? null
                  : () => setState(
                      () => sets.add(
                        fields(sets.last.reps.text, sets.last.weight.text),
                      ),
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
                    final initial = widget.initial;
                    final exercise = Exercise(
                      planExerciseId: initial?.planExerciseId,
                      // A renamed exercise is no longer the catalog entry.
                      exerciseId: initial?.name == name.text.trim()
                          ? initial?.exerciseId
                          : null,
                      name: name.text.trim(),
                      // Mobility and stretching stay what they were while
                      // timed; this screen only switches strength and cardio.
                      kind: !cardio
                          ? 'strength'
                          : initial != null && initial.isTimed
                          ? initial.kind
                          : 'cardio',
                      notes: initial?.notes ?? '',
                      sets: cardio
                          ? const []
                          : [
                              for (final s in sets)
                                ExerciseSet(
                                  int.parse(s.reps.text.trim()),
                                  decimal(s.weight),
                                ),
                            ],
                      minutes: cardio ? decimal(minutes) : null,
                      avgBpm: cardio && bpm.text.trim().isNotEmpty
                          ? int.parse(bpm.text.trim())
                          : null,
                    );
                    setState(() {
                      saving = true;
                      saveError = null;
                    });
                    try {
                      await widget.onSave?.call(exercise);
                      if (context.mounted) Navigator.of(context).pop(exercise);
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
