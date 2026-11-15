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
        child: SingleChildScrollView(
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
              const Divider(height: 24),
              SwitchListTile(
                key: const ValueKey('opt-contours'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Contours'),
                subtitle: const Text(
                  'From the ground surface: points with levels, bending at breaklines (road edges, banks, drains). '
                  'Roofs and wires are left out.',
                ),
                value: o.contours,
                onChanged: (v) => setState(() => o = o.copyWith(contours: v)),
              ),
              if (o.contours) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<double>(
                        key: const ValueKey('opt-interval'),
                        initialValue: o.contourInterval,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Every'),
                        items: [
                          const DropdownMenuItem(value: 0.0, child: Text('Chosen for the ground')),
                          for (final i in DraftOptions.intervals) DropdownMenuItem(value: i, child: Text('$i m')),
                        ],
                        onChanged: (v) => setState(() => o = o.copyWith(contourInterval: v ?? 0)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: o.majorEvery,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Major (labelled) every'),
                        items: [
                          for (final m in const [2, 4, 5, 10]) DropdownMenuItem(value: m, child: Text('$m contours')),
                        ],
                        onChanged: (v) => setState(() => o = o.copyWith(majorEvery: v ?? 5)),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show the triangles (TIN)'),
                  subtitle: const Text('The ground surface the contours come from: to check it, and for Civil 3D.'),
                  value: o.showTin,
                  onChanged: (v) => setState(() => o = o.copyWith(showTin: v)),
                ),
              ],
            ],
          ),
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
