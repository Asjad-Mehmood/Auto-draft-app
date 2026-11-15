// Drawing settings: the scale, text and symbol sizes on paper, which labels are written, and
// whether lines carry their levels (3D).
import 'package:flutter/material.dart';

import '../engine/drawing.dart';
import '../ui/theme.dart';

Future<DraftOptions?> showOptionsDialog(BuildContext context, DraftOptions o) =>
    showDialog<DraftOptions>(context: context, builder: (_) => _OptionsDialog(o));

class _OptionsDialog extends StatefulWidget {
  const _OptionsDialog(this.o);
  final DraftOptions o;

  @override
  State<_OptionsDialog> createState() => _OptionsDialogState();
}

class _OptionsDialogState extends State<_OptionsDialog> {
  late DraftOptions o = widget.o;

  Widget _mm(String label, double value, List<double> choices, ValueChanged<double> set) =>
      DropdownButtonFormField<double>(
        initialValue: choices.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [for (final c in choices) DropdownMenuItem(value: c, child: Text('$c mm'))],
        onChanged: (v) => v == null ? null : set(v),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Drawing settings'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const ValueKey('opt-scale'),
                    initialValue: DraftOptions.scales.contains(o.scale) ? o.scale : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Scale'),
                    items: [for (final s in DraftOptions.scales) DropdownMenuItem(value: s, child: Text('1:$s'))],
                    onChanged: (v) => setState(() => o = o.copyWith(scale: v)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: o.levelDecimals,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Level decimals'),
                    items: [
                      for (var d = 0; d <= 4; d++)
                        DropdownMenuItem(value: d, child: Text(d == 0 ? '214' : '214.${'3567'.substring(0, d)}')),
                    ],
                    onChanged: (v) => setState(() => o = o.copyWith(levelDecimals: v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _mm('Text height on paper', o.textMm, const [
                    1.0,
                    1.5,
                    1.8,
                    2.0,
                    2.5,
                    3.0,
                    3.5,
                  ], (v) => setState(() => o = o.copyWith(textMm: v))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _mm('Symbol size on paper', o.symbolMm, const [
                    1.5,
                    2.0,
                    2.5,
                    3.0,
                    4.0,
                    5.0,
                  ], (v) => setState(() => o = o.copyWith(symbolMm: v))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'At 1:${o.scale}: text ${o.textHeight.toStringAsFixed(2)} m high, symbols ${o.symbolSize.toStringAsFixed(2)} m wide on the ground.',
              style: const TextStyle(color: Tone.muted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Write levels'),
              value: o.levels,
              onChanged: (v) => setState(() => o = o.copyWith(levels: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Write point numbers'),
              value: o.pointNumbers,
              onChanged: (v) => setState(() => o = o.copyWith(pointNumbers: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Write codes'),
              value: o.codes,
              onChanged: (v) => setState(() => o = o.copyWith(codes: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('3D lines (at their levels)'),
              subtitle: const Text(
                'For Civil 3D surfaces and sections. Off: flat lines at level 0, as most drawings are.',
              ),
              value: o.lines3d,
              onChanged: (v) => setState(() => o = o.copyWith(lines3d: v)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => setState(() => o = const DraftOptions()), child: const Text('Defaults')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, o), child: const Text('Apply')),
      ],
    );
  }
}
