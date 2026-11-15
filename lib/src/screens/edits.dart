// The edits a person makes while checking the drawing, shared by the side panel, the drawing and
// the menu: a point's code, every point with one code, and the code list.
import 'package:flutter/material.dart';

import '../engine/codes.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import 'code_dialog.dart';

/// A snack bar whose Undo undoes the step just made
void sayDone(BuildContext context, AppState state, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(
    SnackBar(
      content: Text(text),
      action: SnackBarAction(label: 'Undo', onPressed: state.undo),
      duration: const Duration(seconds: 5),
    ),
  );

/// Changes the code of the point at [index]
Future<void> editPointCode(BuildContext context, AppState state, int index) async {
  final p = state.points[index];
  final was = state.fileCodeOf(index);
  final c = TextEditingController(text: p.code);
  final code = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Code of point ${p.id}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('point-code'),
              controller: c,
              autofocus: true,
              style: mono.copyWith(fontSize: 15),
              decoration: const InputDecoration(helperText: 'For example: RE1, RE1 ST, BLD2 CLS, TR'),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            if (was != null) ...[
              const SizedBox(height: 10),
              Text(
                'In the file: ${was.isEmpty ? '(no code)' : was}',
                style: const TextStyle(color: Tone.muted, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Redraw')),
      ],
    ),
  );
  if (code != null && code.trim() != p.code && context.mounted) {
    state.setCode(index, code);
    sayDone(context, state, 'Point ${p.id} is now ${code.trim().isEmpty ? 'without a code' : code.trim()}.');
  }
}

/// Changes the first word of every point coded [from] ("XX" → "TR")
Future<void> replaceEverywhere(BuildContext context, AppState state, String from) async {
  final c = TextEditingController();
  final to = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final t = c.text.trim();
        return AlertDialog(
          title: Text('Change $from on every point'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Every point coded $from gets the new code. Words after it (ST, END…) stay.',
                  style: const TextStyle(color: Tone.muted),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('replace-to'),
                  controller: c,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  style: mono.copyWith(fontSize: 15),
                  decoration: InputDecoration(
                    labelText: 'New code',
                    helperText: t.isEmpty
                        ? 'For example TR, or RE1'
                        : (state.library.contains(t.replaceFirst(RegExp(r'\d+$'), '')) || state.library.contains(t)
                              ? '✓ in the code list'
                              : 'Not in the code list yet'),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) => v.trim().isEmpty ? null : Navigator.pop(context, v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: t.isEmpty ? null : () => Navigator.pop(context, t),
              child: const Text('Change all'),
            ),
          ],
        );
      },
    ),
  );
  if (to == null || to.trim().isEmpty || !context.mounted) return;
  final n = state.replaceCode(from, to.trim().toUpperCase());
  sayDone(context, state, '$from changed to ${to.trim().toUpperCase()} on $n point${n == 1 ? '' : 's'}.');
}

/// Adds a code (starting from [suggest]) or changes [existing]
Future<void> editCode(BuildContext context, AppState state, {FeatureCode? existing, String suggest = ''}) async {
  final r = await showCodeDialog(context, state.library, existing: existing, suggest: suggest);
  if (r == null || !context.mounted) return;
  if (r.delete) {
    state.deleteCode(existing!.code);
    sayDone(context, state, 'Code ${existing.code} removed from the list.');
  } else {
    state.saveCode(r.code!, replacing: existing?.code);
    sayDone(context, state, existing == null ? 'Code ${r.code!.code} added.' : 'Code ${r.code!.code} saved.');
  }
}
