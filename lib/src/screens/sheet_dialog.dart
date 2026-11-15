// The printed sheet: paper (or the smallest the survey fits on), and what the title block says.
// Whether the survey fits is shown as it is changed.
import 'package:flutter/material.dart';

import '../engine/drawing.dart';
import '../engine/sheet.dart';
import '../ui/theme.dart';

Future<SheetInfo?> showSheetDialog(BuildContext context, SheetInfo info, Drawing drawing) =>
    showDialog<SheetInfo>(context: context, builder: (_) => _SheetDialog(info, drawing));

String today() {
  final d = DateTime.now();
  return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
}

class _SheetDialog extends StatefulWidget {
  const _SheetDialog(this.info, this.drawing);
  final SheetInfo info;
  final Drawing drawing;

  @override
  State<_SheetDialog> createState() => _SheetDialogState();
}

class _SheetDialogState extends State<_SheetDialog> {
  late SheetInfo i = widget.info.date.isEmpty ? widget.info.copyWith(date: today()) : widget.info;
  late final _c = {
    'firm': TextEditingController(text: i.firm),
    'title': TextEditingController(text: i.title),
    'location': TextEditingController(text: i.location),
    'client': TextEditingController(text: i.client),
    'surveyedBy': TextEditingController(text: i.surveyedBy),
    'date': TextEditingController(text: i.date),
    'drawnBy': TextEditingController(text: i.drawnBy),
    'drawingNo': TextEditingController(text: i.drawingNo),
    'sheetNo': TextEditingController(text: i.sheetNo),
    'notes': TextEditingController(text: i.notes),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  SheetInfo get result => i.copyWith(
    firm: _c['firm']!.text.trim(),
    title: _c['title']!.text.trim(),
    location: _c['location']!.text.trim(),
    client: _c['client']!.text.trim(),
    surveyedBy: _c['surveyedBy']!.text.trim(),
    date: _c['date']!.text.trim(),
    drawnBy: _c['drawnBy']!.text.trim(),
    drawingNo: _c['drawingNo']!.text.trim(),
    sheetNo: _c['sheetNo']!.text.trim(),
    notes: _c['notes']!.text.trim(),
  );

  Widget _field(String key, String label, {String hint = '', int lines = 1}) => TextField(
    key: ValueKey('sheet-$key'),
    controller: _c[key],
    maxLines: lines,
    decoration: InputDecoration(labelText: label, hintText: hint.isEmpty ? null : hint),
  );

  @override
  Widget build(BuildContext context) {
    final sheet = buildSheet(widget.drawing, i);
    return AlertDialog(
      title: const Text('Sheet and title block'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<Paper?>(
                      key: const ValueKey('sheet-paper'),
                      initialValue: i.paper,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Paper'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Smallest that fits')),
                        for (final p in Paper.values)
                          DropdownMenuItem(
                            value: p,
                            child: Text('${p.label}  (${p.width.round()} × ${p.height.round()} mm)'),
                          ),
                      ],
                      onChanged: (v) => setState(() => i = i.copyWith(paper: () => v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Landscape')),
                      ButtonSegment(value: true, label: Text('Portrait')),
                    ],
                    selected: {i.paper == null ? sheet.portrait : i.portrait},
                    onSelectionChanged: i.paper == null
                        ? null
                        : (v) => setState(() => i = i.copyWith(portrait: v.first)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // does it fit?
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: (sheet.fits ? Tone.ok : Tone.warning).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: (sheet.fits ? Tone.ok : Tone.warning).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(
                      sheet.fits ? Icons.check_circle : Icons.warning_amber_rounded,
                      size: 18,
                      color: sheet.fits ? Tone.ok : Tone.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        sheet.fits
                            ? 'Fits on ${sheet.label}. Grid every ${sheet.gridInterval.round()} m.'
                            : 'Doesn\'t fit on ${sheet.label}. ${sheet.advice}',
                        style: TextStyle(fontWeight: FontWeight.w600, color: sheet.fits ? Tone.ok : Tone.warning),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _field('firm', 'Firm', hint: 'Your company'),
              const SizedBox(height: 12),
              _field('title', 'Drawing title', hint: 'Topographic survey of …'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _field('location', 'Location')),
                  const SizedBox(width: 12),
                  Expanded(child: _field('client', 'Client')),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _field('surveyedBy', 'Surveyed by')),
                  const SizedBox(width: 12),
                  Expanded(child: _field('date', 'Date')),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _field('drawnBy', 'Drawn by')),
                  const SizedBox(width: 12),
                  Expanded(child: _field('drawingNo', 'Drawing no.')),
                  const SizedBox(width: 12),
                  SizedBox(width: 110, child: _field('sheetNo', 'Sheet')),
                ],
              ),
              const SizedBox(height: 12),
              _field('notes', 'Notes', lines: 2),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show the sheet on screen and in the DXF'),
                subtitle: const Text('Off: the DXF has the survey only. The PDF always has the sheet.'),
                value: i.inDxf,
                onChanged: (v) => setState(() => i = i.copyWith(inDxf: v)),
              ),
              const Text(
                'The firm, the people, the notes and the paper are remembered for the next survey.',
                style: TextStyle(color: Tone.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, result), child: const Text('Apply')),
      ],
    );
  }
}
