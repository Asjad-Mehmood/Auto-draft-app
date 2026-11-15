// After a file is opened: which column is the point number, easting, northing, level and code.
// The guess is filled in; the first lines of the file are shown with each column's role, so a
// wrong guess is easy to see and change.
import 'package:flutter/material.dart';

import '../engine/import.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';

Future<ColumnMap?> showColumnsDialog(BuildContext context, OpenedFile f) =>
    showDialog<ColumnMap>(context: context, builder: (_) => _ColumnsDialog(f));

class _ColumnsDialog extends StatefulWidget {
  const _ColumnsDialog(this.f);
  final OpenedFile f;

  @override
  State<_ColumnsDialog> createState() => _ColumnsDialogState();
}

class _ColumnsDialogState extends State<_ColumnsDialog> {
  late ColumnMap m = widget.f.guess;

  static const _roles = [
    ('id', 'Point number'),
    ('e', 'Easting (X)'),
    ('n', 'Northing (Y)'),
    ('z', 'Level (Z)'),
    ('code', 'Code'),
  ];

  int _get(String role) => switch (role) {
    'id' => m.id,
    'e' => m.e,
    'n' => m.n,
    'z' => m.z,
    _ => m.code,
  };

  ColumnMap _set(String role, int c) => switch (role) {
    'id' => m.copyWith(id: c),
    'e' => m.copyWith(e: c),
    'n' => m.copyWith(n: c),
    'z' => m.copyWith(z: c),
    _ => m.copyWith(code: c),
  };

  String? _roleOf(int c) {
    for (final (r, label) in _roles) {
      if (_get(r) == c) return label;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.f.table;
    final cols = t.columns;
    final read = readPoints(t, m);
    final ok = m.e >= 0 && m.n >= 0 && m.e != m.n && read.points.isNotEmpty;
    final preview = t.rows.take(m.headerRows + 8).toList();
    return AlertDialog(
      title: Text('Columns in ${widget.f.name}'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.f.format.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Tone.info.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Tone.info.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    '${widget.f.format} file: ${widget.f.notes.join('; ')}.',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Tone.info),
                  ),
                )
              else
                const Text(
                  'Check which column holds what. The guess is filled in.',
                  style: TextStyle(color: Tone.muted),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (role, label) in _roles)
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('col-$role'),
                        initialValue: _get(role),
                        isExpanded: true,
                        decoration: InputDecoration(labelText: label),
                        items: [
                          DropdownMenuItem(value: -1, child: Text(role == 'e' || role == 'n' ? '(choose)' : 'None')),
                          for (var c = 0; c < cols; c++) DropdownMenuItem(value: c, child: Text('Column ${c + 1}')),
                        ],
                        onChanged: (v) => setState(() => m = _set(role, v ?? -1)),
                      ),
                    ),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<int>(
                      key: const ValueKey('col-header'),
                      initialValue: m.headerRows,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Title lines at top'),
                      items: [for (var h = 0; h <= 5; h++) DropdownMenuItem(value: h, child: Text('$h'))],
                      onChanged: (v) => setState(() => m = m.copyWith(headerRows: v ?? 0)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // the first lines, each column headed by what it is used for
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Tone.line),
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 30,
                    dataRowMaxHeight: 32,
                    horizontalMargin: 14,
                    columnSpacing: 22,
                    headingRowColor: const WidgetStatePropertyAll(Tone.soft),
                    columns: [
                      for (var c = 0; c < cols; c++)
                        DataColumn(
                          label: Text(
                            _roleOf(c) ?? 'Column ${c + 1} (not used)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _roleOf(c) == null ? Tone.muted : Tone.ink,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                    ],
                    rows: [
                      for (var i = 0; i < preview.length; i++)
                        DataRow(
                          color: WidgetStatePropertyAll(i < m.headerRows ? const Color(0xFFF0F2F6) : null),
                          cells: [
                            for (var c = 0; c < cols; c++)
                              DataCell(
                                Text(
                                  c < preview[i].length ? preview[i][c] : '',
                                  style: mono.copyWith(color: i < m.headerRows ? Tone.muted : Tone.ink),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                ok
                    ? '${read.points.length} points read'
                          '${read.skipped.isEmpty ? '' : ', ${read.skipped.length} lines skipped (first: line ${read.skipped.first.$1}, ${read.skipped.first.$2})'}.'
                    : 'Choose the easting and northing columns.',
                style: TextStyle(fontWeight: FontWeight.w600, color: ok ? Tone.ok : Tone.error),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: ok ? () => Navigator.pop(context, m) : null, child: const Text('Draw it')),
      ],
    );
  }
}
