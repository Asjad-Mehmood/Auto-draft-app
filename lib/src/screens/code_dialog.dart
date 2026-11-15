// Adding or changing a code: what the surveyor types, what it is, line or point, and how it is
// drawn (layer, colour, line type or symbol). Checked as it is typed: a code must be new, start
// with a letter and not be a control word; a layer name must suit DXF.
import 'package:flutter/material.dart';

import '../engine/codes.dart';
import '../engine/symbols.dart';
import '../ui/aci.dart';
import '../ui/symbol_icon.dart';
import '../ui/theme.dart';

/// What the dialog decided: a code to save, or the code to remove
class CodeEdit {
  const CodeEdit.save(FeatureCode this.code) : delete = false;
  const CodeEdit.delete() : code = null, delete = true;
  final FeatureCode? code;
  final bool delete;
}

/// [existing]: the code being changed (null: a new one). [suggest]: a code to start with ("XX").
Future<CodeEdit?> showCodeDialog(
  BuildContext context,
  CodeLibrary library, {
  FeatureCode? existing,
  String suggest = '',
}) => showDialog<CodeEdit>(context: context, builder: (_) => _CodeDialog(library, existing, suggest));

/// The colours offered as swatches (AutoCAD colour numbers); any 1–255 can be typed
const _swatches = [1, 2, 3, 4, 5, 6, 7, 8, 9, 30, 40, 42, 140, 150, 160, 200, 210, 230];

/// A layer name from what the code is: "Boundary pillar" → "BOUNDARY_PILLAR"
String layerFor(String name) {
  final l = name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return l.length > 31 ? l.substring(0, 31) : l;
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog(this.library, this.existing, this.suggest);
  final CodeLibrary library;
  final FeatureCode? existing;
  final String suggest;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  late final _code = TextEditingController(text: widget.existing?.code ?? widget.suggest.toUpperCase());
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _layer = TextEditingController(text: widget.existing?.layer ?? '');
  late final _color = TextEditingController(text: '${widget.existing?.color ?? 7}');
  late CodeKind _kind = widget.existing?.kind ?? CodeKind.point;
  late String _lineType = widget.existing?.lineType ?? 'CONTINUOUS';
  late String _symbol = (widget.existing?.symbol.isNotEmpty ?? false) ? widget.existing!.symbol : 'AD_SPOT';
  late bool _levels = widget.existing?.levels ?? true;
  late bool _breakline = widget.existing?.breakline ?? false;
  late bool _surface = widget.existing?.surface ?? true;

  /// The layer follows the name until it is typed by hand
  late bool _layerByHand = widget.existing != null;

  @override
  void dispose() {
    for (final c in [_code, _name, _layer, _color]) {
      c.dispose();
    }
    super.dispose();
  }

  String get code => _code.text.trim().toUpperCase();
  int? get color {
    final v = int.tryParse(_color.text.trim());
    return v != null && v >= 1 && v <= 255 ? v : null;
  }

  String? get codeError {
    if (code.isEmpty) return 'Type the code';
    if (isControlWord(code)) return '$code is a control word (ST, END, CLS, ARC, EARC, RECT)';
    if (!validCode(code)) return 'Letters first, then letters or digits, up to 12';
    final other = widget.library[code];
    if (other != null && other.code != widget.existing?.code) return '$code is already ${other.name}';
    return null;
  }

  String? get layerError {
    final l = _layer.text.trim();
    if (l.isEmpty) return 'Type a layer name';
    if (!validLayer(l)) return 'Letters, digits, _ - and \$ only, up to 31';
    return null;
  }

  bool get ok => codeError == null && layerError == null && color != null && _name.text.trim().isNotEmpty;

  FeatureCode get result => FeatureCode(
    code: code,
    name: _name.text.trim(),
    kind: _kind,
    layer: _layer.text.trim().toUpperCase(),
    color: color!,
    lineType: _kind == CodeKind.line ? _lineType : 'CONTINUOUS',
    symbol: _kind == CodeKind.point ? _symbol : '',
    levels: _levels,
    breakline: _kind == CodeKind.line && _breakline,
    surface: _surface,
  );

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Code ${widget.existing!.code}' : 'A new code'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      key: const ValueKey('code-code'),
                      controller: _code,
                      autofocus: !editing,
                      textCapitalization: TextCapitalization.characters,
                      style: mono.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        labelText: 'Code',
                        errorText: _code.text.isEmpty ? null : codeError,
                        errorMaxLines: 3,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('code-name'),
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'What it is', hintText: 'Boundary pillar'),
                      onChanged: (v) => setState(() {
                        if (!_layerByHand) _layer.text = layerFor(v);
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SegmentedButton<CodeKind>(
                segments: const [
                  ButtonSegment(
                    value: CodeKind.line,
                    icon: Icon(Icons.timeline),
                    label: Text('Line: joins its points'),
                  ),
                  ButtonSegment(
                    value: CodeKind.point,
                    icon: Icon(Icons.place_outlined),
                    label: Text('Point: a symbol'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('code-layer'),
                      controller: _layer,
                      textCapitalization: TextCapitalization.characters,
                      style: mono,
                      decoration: InputDecoration(
                        labelText: 'Layer',
                        errorText: _layer.text.isEmpty ? null : layerError,
                      ),
                      onChanged: (_) => setState(() => _layerByHand = true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _kind == CodeKind.line
                        ? DropdownButtonFormField<String>(
                            initialValue: _lineType,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Line type'),
                            items: [
                              for (final t in lineTypes) DropdownMenuItem(value: t, child: Text(_lineTypeName(t))),
                            ],
                            onChanged: (v) => setState(() => _lineType = v ?? 'CONTINUOUS'),
                          )
                        : DropdownButtonFormField<String>(
                            initialValue: _symbol,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Symbol'),
                            items: [
                              for (final s in symbols.values)
                                DropdownMenuItem(
                                  value: s.name,
                                  child: Row(
                                    children: [
                                      SymbolIcon(s.name, size: 18),
                                      const SizedBox(width: 10),
                                      Flexible(child: Text(s.label, overflow: TextOverflow.ellipsis)),
                                    ],
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() => _symbol = v ?? 'AD_SPOT'),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Colour', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in _swatches)
                          Tooltip(
                            message: 'Colour $c',
                            child: InkWell(
                              onTap: () => setState(() => _color.text = '$c'),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: aciColor(c),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: color == c ? Tone.ink : Tone.line,
                                    width: color == c ? 2.5 : 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _color,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Number', errorText: color == null ? '1 to 255' : null),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Write the level of its points'),
                value: _levels,
                onChanged: (v) => setState(() => _levels = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('On the ground (used for contours)'),
                subtitle: const Text('Off for roofs, wires and pipes'),
                value: _surface,
                onChanged: (v) => setState(() => _surface = v),
              ),
              if (_kind == CodeKind.line)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Breakline'),
                  subtitle: const Text('The ground changes along it (road edge, bank, drain): contours bend here'),
                  value: _breakline,
                  onChanged: (v) => setState(() => _breakline = v),
                ),
              // how it will look
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFF0B1220), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      height: 26,
                      child: _kind == CodeKind.line
                          ? CustomPaint(painter: _LinePreview(aciOnDark(color ?? 7), _lineType))
                          : Center(child: SymbolIcon(_symbol, size: 24, color: aciOnDark(color ?? 7))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '${code.isEmpty ? '…' : code}${_kind == CodeKind.line ? '1, ${code.isEmpty ? '…' : code}2' : ''}  →  layer ${_layer.text.trim().isEmpty ? '…' : _layer.text.trim().toUpperCase()}',
                        style: mono.copyWith(color: const Color(0xFFDCE4F2)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (editing)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Tone.error),
            onPressed: () => Navigator.pop(context, const CodeEdit.delete()),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Remove'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: ok ? () => Navigator.pop(context, CodeEdit.save(result)) : null,
          child: Text(editing ? 'Save' : 'Add code'),
        ),
      ],
    );
  }
}

String _lineTypeName(String t) => switch (t) {
  'CONTINUOUS' => 'Solid ────',
  'DASHED' => 'Dashed — — —',
  'HIDDEN' => 'Hidden - - - -',
  'CENTER' => 'Centre ── - ──',
  'DASHDOT' => 'Dash dot — · —',
  'DOT' => 'Dotted · · · ·',
  _ => t,
};

class _LinePreview extends CustomPainter {
  _LinePreview(this.color, this.type);
  final Color color;
  final String type;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    final pattern = switch (type) {
      'DASHED' => [10.0, 6.0],
      'HIDDEN' => [5.0, 4.0],
      'CENTER' => [18.0, 4.0, 4.0, 4.0],
      'DASHDOT' => [10.0, 4.0, 1.5, 4.0],
      'DOT' => [1.5, 4.0],
      _ => [size.width, 0.0],
    };
    final y = size.height / 2;
    var x = 0.0, i = 0;
    while (x < size.width) {
      final len = pattern[i % pattern.length];
      if (i.isEven) canvas.drawLine(Offset(x, y), Offset((x + len).clamp(0, size.width), y), paint);
      x += len;
      i++;
    }
  }

  @override
  bool shouldRepaint(_LinePreview old) => old.color != color || old.type != type;
}
