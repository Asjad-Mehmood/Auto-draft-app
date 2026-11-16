// PDF to drawing: a PDF printed from CAD is redrawn as a proper drawing (joined polylines, arcs and
// circles, line types, hatches, dimensions, text, layers) and saved as a DXF. The person picks the
// page and the scale; the drawing's dimensions suggest the scale when it has any.
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../account/account.dart';
import '../brand.dart';
import '../engine/aci.dart';
import '../engine/pdf_in/pdf_drafting.dart';
import '../state/files.dart';
import '../ui/theme.dart';

/// What the drafting gives back to the screen
class PdfDraftResult {
  PdfDraftResult(this.drawing, this.pageCount, this.pdfLayers, this.suggestedScale);
  final CadDrawing drawing;
  final int pageCount;
  final int pdfLayers;
  final int? suggestedScale;
}

/// Drafts in the background, so a big drawing doesn't freeze the window; the tests run it directly
typedef DraftRunner = Future<PdfDraftResult> Function(PdfDraftResult Function() work);

Future<PdfDraftResult> backgroundDraft(PdfDraftResult Function() work) => Isolate.run(work);

/// The drafting, as a job for the background. Made here, outside the screen: a function made
/// inside the screen's (async) code would carry the screen with it, and the background can't take
/// that ("object is unsendable"). This one holds only the PDF's bytes and the three choices.
PdfDraftResult Function() draftJob(Uint8List bytes, int page, int scale, bool useLayers) => () {
  final f = PdfDrawingFile.open(bytes);
  final d = f.draft(
    page,
    options: PdfDraftOptions(scale: scale > 0 ? scale : null, useLayers: useLayers),
    autoScale: scale == _autoScale,
  );
  return PdfDraftResult(d.drawing, f.pageCount, f.layerNames.length, d.suggestedScale);
};

/// 0: the scale the dimensions show; -1: millimetres, as printed; else 1:n
const _autoScale = 0, _paperScale = -1;
const _scales = [50, 100, 200, 250, 500, 1000, 1250, 2000, 2500, 5000];

class PdfDraftScreen extends StatefulWidget {
  const PdfDraftScreen({
    super.key,
    required this.name,
    required this.bytes,
    required this.files,
    required this.account,
    this.runner = backgroundDraft,
  });
  final String name;
  final Uint8List bytes;
  final FileIo files;
  final Account account;
  final DraftRunner runner;

  @override
  State<PdfDraftScreen> createState() => _PdfDraftScreenState();
}

class _PdfDraftScreenState extends State<PdfDraftScreen> {
  int _page = 0;
  int _scale = _autoScale;
  bool _useLayers = true;
  PdfDraftResult? _result;
  String? _error;
  bool _busy = true;
  final _hidden = <String>{};
  int _run = 0;

  String get _base => widget.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');

  @override
  void initState() {
    super.initState();
    _draft();
  }

  Future<void> _draft() async {
    final run = ++_run;
    setState(() {
      _busy = true;
      _error = null;
    });
    final bytes = widget.bytes, page = _page, scale = _scale, layers = _useLayers;
    try {
      final r = await widget.runner(draftJob(bytes, page, scale, layers));
      if (!mounted || run != _run) return;
      setState(() {
        _result = r;
        _busy = false;
        _hidden.removeWhere((l) => !r.drawing.layers.containsKey(l));
      });
    } catch (e) {
      if (!mounted || run != _run) return;
      setState(() {
        _busy = false;
        _error = e is PdfReadError ? e.message : 'This PDF couldn\'t be read: $e';
      });
    }
  }

  Future<void> _save() async {
    final d = _result?.drawing;
    if (d == null) return;
    final bytes = ascii.encode(pdfDrawingToDxf(d));
    final path = await widget.files.save(
      suggestedName: '$_base.dxf',
      label: 'AutoCAD drawing (DXF)',
      extensions: const ['dxf'],
      bytes: bytes,
    );
    if (path == null) return;
    unawaited(
      widget.account.report(
        title: 'Saved DXF from a PDF drawing',
        format: 'DXF',
        fileName: '$_base.dxf',
        fileSize: bytes.length,
        points: 0,
        lines: d.entities.length,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved $path. Open it in AutoCAD, BricsCAD or any CAD program; save it there as a DWG if you need one.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final d = r?.drawing;
    return Scaffold(
      body: Column(
        children: [
          // ---- the bar
          Container(
            color: BrandColors.navy,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.picture_as_pdf_outlined, color: BrandColors.goldLight, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'PDF drawing · ${widget.name}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                const Spacer(),
                if (r != null && r.pageCount > 1) ...[
                  const _BarLabel('Page'),
                  _BarDrop<int>(
                    value: _page,
                    items: {for (var i = 0; i < r.pageCount; i++) i: '${i + 1} of ${r.pageCount}'},
                    onChanged: (v) {
                      _page = v;
                      _draft();
                    },
                  ),
                  const SizedBox(width: 14),
                ],
                const _BarLabel('Scale'),
                _BarDrop<int>(
                  value: _scale,
                  items: {
                    _autoScale: r?.suggestedScale != null
                        ? 'From its dimensions (1:${r!.suggestedScale})'
                        : 'From its dimensions',
                    _paperScale: 'As printed (millimetres)',
                    for (final s in _scales) s: '1:$s (metres)',
                  },
                  onChanged: (v) {
                    _scale = v;
                    _draft();
                  },
                ),
                const SizedBox(width: 14),
                FilledButton.icon(
                  style: goldButton(),
                  onPressed: d == null || _busy ? null : _save,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save DXF'),
                ),
              ],
            ),
          ),
          // ---- the drawing and its summary
          Expanded(
            child: _error != null
                ? _Message(icon: Icons.error_outline, color: Tone.error, text: _error!)
                : d == null
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: _Preview(drawing: d, hidden: _hidden),
                            ),
                            if (_busy) const Positioned(top: 12, left: 12, child: CircularProgressIndicator()),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 360,
                        child: _Summary(
                          result: r!,
                          hidden: _hidden,
                          onToggle: _toggle,
                          useLayers: _useLayers,
                          onUseLayers: _setUseLayers,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _toggle(String layer) => setState(() => _hidden.contains(layer) ? _hidden.remove(layer) : _hidden.add(layer));

  void _setUseLayers(bool v) {
    _useLayers = v;
    _draft();
  }
}

class _BarLabel extends StatelessWidget {
  const _BarLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Text(text, style: const TextStyle(color: Color(0xFFB9C6DE), fontSize: 13)),
  );
}

class _BarDrop<T> extends StatelessWidget {
  const _BarDrop({required this.value, required this.items, required this.onChanged});
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        items: [
          for (final e in items.entries)
            DropdownMenuItem(
              value: e.key,
              child: Text(e.value, style: const TextStyle(fontSize: 13)),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 40),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.4)),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------------------------
// The summary: what was found, the notes, the layers
// ---------------------------------------------------------------------------------------------

class _Summary extends StatelessWidget {
  const _Summary({
    required this.result,
    required this.hidden,
    required this.onToggle,
    required this.useLayers,
    required this.onUseLayers,
  });
  final PdfDraftResult result;
  final Set<String> hidden;
  final ValueChanged<String> onToggle;
  final bool useLayers;
  final ValueChanged<bool> onUseLayers;

  @override
  Widget build(BuildContext context) {
    final d = result.drawing;
    final counts = d.counts;
    final perLayer = <String, int>{};
    for (final e in d.entities) {
      perLayer[e.style.layer] = (perLayer[e.style.layer] ?? 0) + 1;
    }
    const order = ['polylines', 'lines', 'arcs', 'circles', 'hatches', 'dimensions', 'texts'];
    String plural(String k, int n) => n == 1 ? k.substring(0, k.length - 1) : k;
    return Material(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            d.units == 'm' ? 'Drawn in metres at 1:${d.scale}' : 'Drawn in millimetres, as printed',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            d.units == 'm'
                ? 'Lengths, text and dimensions are real sizes on the ground.'
                : 'Choose the drawing\'s scale above to get real sizes in metres.',
            style: const TextStyle(color: Tone.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in order)
                if ((counts[k] ?? 0) > 0)
                  Chip(label: Text('${counts[k]} ${plural(k, counts[k]!)}'), visualDensity: VisualDensity.compact),
            ],
          ),
          for (final n in d.notes) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6E0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF2D58A)),
              ),
              child: Text(n, style: const TextStyle(fontSize: 12.5, height: 1.35)),
            ),
          ],
          if (result.pdfLayers > 0) ...[
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('Use the PDF\'s own ${result.pdfLayers} layers'),
              subtitle: const Text('Off: one layer per colour and line type'),
              value: useLayers,
              onChanged: onUseLayers,
            ),
          ],
          const SizedBox(height: 14),
          Text('Layers (${d.layers.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final l in d.layers.values)
            InkWell(
              onTap: () => onToggle(l.name),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      hidden.contains(l.name) ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18,
                      color: Tone.muted,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _paper(l.aci),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Tone.line),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${l.lineType == 'CONTINUOUS' ? '' : '${l.lineType} · '}${perLayer[l.name] ?? 0}',
                      style: const TextStyle(fontSize: 12, color: Tone.muted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Color _paper(int aci) {
  final (r, g, b) = aciOnPaper(aci);
  return Color.fromARGB(255, r, g, b);
}

// ---------------------------------------------------------------------------------------------
// The preview
// ---------------------------------------------------------------------------------------------

class _Preview extends StatelessWidget {
  const _Preview({required this.drawing, required this.hidden});
  final CadDrawing drawing;
  final Set<String> hidden;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Tone.soft,
    child: LayoutBuilder(
      builder: (context, c) => InteractiveViewer(
        maxScale: 40,
        minScale: 0.5,
        child: SizedBox(
          width: c.maxWidth,
          height: c.maxHeight,
          child: CustomPaint(painter: _CadPainter(drawing, hidden)),
        ),
      ),
    ),
  );
}

class _CadPainter extends CustomPainter {
  _CadPainter(this.d, this.hidden);
  final CadDrawing d;
  final Set<String> hidden;

  @override
  void paint(Canvas canvas, Size size) {
    final b = d.bounds;
    if (b == null) return;
    const margin = 24.0;
    final w = math.max(b.maxX - b.minX, 1e-6), h = math.max(b.maxY - b.minY, 1e-6);
    final k = math.min((size.width - 2 * margin) / w, (size.height - 2 * margin) / h);
    final ox = (size.width - w * k) / 2, oy = (size.height - h * k) / 2;
    Offset p(double x, double y) => Offset(ox + (x - b.minX) * k, size.height - oy - (y - b.minY) * k);
    // paper: a line a pixel wide, a little more for heavier lineweights
    Color colour(CadStyle s) => _paper(s.aci == 256 ? (d.layers[s.layer]?.aci ?? 7) : s.aci);

    void draw(CadEntity e, [CadStyle? as]) {
      final st = as ?? e.style;
      if (hidden.contains(st.layer)) return;
      final pen = Paint()
        ..color = colour(st)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      // the line type's dashes, in screen pixels
      final lt = st.lineType == 'BYLAYER' ? (d.layers[st.layer]?.lineType ?? 'CONTINUOUS') : st.lineType;
      final pattern = [for (final x in standardLineTypes[lt]?.$2 ?? const <double>[]) x * st.ltScale * k];
      void stroke(Path path) => canvas.drawPath(pattern.isEmpty ? path : _dashed(path, pattern), pen);
      switch (e) {
        case CadLine():
          final a = p(e.x1, e.y1), b2 = p(e.x2, e.y2);
          stroke(
            Path()
              ..moveTo(a.dx, a.dy)
              ..lineTo(b2.dx, b2.dy),
          );
        case CadPolyline():
          stroke(_path(e.vertices, e.closed, p, k));
        case CadCircle():
          stroke(Path()..addOval(Rect.fromCircle(center: p(e.cx, e.cy), radius: e.r * k)));
        case CadArc():
          final rect = Rect.fromCircle(center: p(e.cx, e.cy), radius: e.r * k);
          var sweep = e.end - e.start;
          if (sweep <= 0) sweep += 360;
          stroke(Path()..addArc(rect, -e.start * math.pi / 180, -sweep * math.pi / 180));
        case CadHatch():
          final path = Path()..fillType = PathFillType.evenOdd;
          for (final l in e.loops) {
            path.addPath(_path(l, true, p, k), Offset.zero);
          }
          if (e.solid) {
            canvas.drawPath(path, Paint()..color = colour(st).withValues(alpha: 0.55));
          } else {
            // the pattern's lines, clipped to the outline
            final families = switch (e.pattern) {
              'ANSI31' => [(45.0 + e.angle, 3.175 * e.patternScale)],
              'ANSI37' => [(45.0 + e.angle, 3.175 * e.patternScale), (135.0 + e.angle, 3.175 * e.patternScale)],
              '_USER_DOUBLE' => [(e.angle, e.spacing), (e.angle + 90, e.spacing)],
              _ => [(e.angle, e.spacing)],
            };
            final box = path.getBounds();
            canvas.save();
            canvas.clipPath(path);
            for (final (ang, sp) in families) {
              final gap = sp * k;
              if (gap < 1.5) continue;
              final a = -ang * math.pi / 180;
              final ux = math.cos(a), uy = math.sin(a);
              final c = box.center;
              final reach = box.longestSide;
              for (var o = -reach; o <= reach; o += gap) {
                final mx = c.dx - uy * o, my = c.dy + ux * o;
                canvas.drawLine(
                  Offset(mx - ux * reach, my - uy * reach),
                  Offset(mx + ux * reach, my + uy * reach),
                  pen,
                );
              }
            }
            canvas.restore();
          }
        case CadText():
          final tp = TextPainter(
            text: TextSpan(
              text: e.text,
              style: TextStyle(
                fontFamily: 'Inter',
                color: colour(st),
                fontSize: math.max(1, e.height * k / 0.72),
                height: 1,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          canvas.save();
          final at = p(e.x, e.y);
          canvas.translate(at.dx, at.dy);
          canvas.rotate(-e.angle * math.pi / 180);
          tp.paint(canvas, Offset(0, -tp.height * 0.8));
          canvas.restore();
        case CadDimension():
          for (final x in e.block) {
            draw(x, st);
          }
      }
    }

    d.entities.forEach(draw);
  }

  /// [path] cut into the dashes of [pattern] (dash > 0, gap < 0, dot 0), in pixels
  static Path _dashed(Path path, List<double> pattern) {
    final period = pattern.fold(0.0, (a, x) => a + x.abs());
    if (period < 2) return path; // too fine to see on screen: solid
    final out = Path();
    for (final m in path.computeMetrics()) {
      var pos = 0.0;
      var i = 0;
      while (pos < m.length) {
        final x = pattern[i % pattern.length];
        if (x >= 0) {
          out.addPath(m.extractPath(pos, math.min(m.length, pos + math.max(x, 0.8))), Offset.zero);
        }
        pos += x.abs();
        i++;
      }
    }
    return out;
  }

  static Path _path(List<CadVertex> v, bool closed, Offset Function(double, double) p, double k) {
    final path = Path();
    if (v.isEmpty) return path;
    path.moveTo(p(v.first.x, v.first.y).dx, p(v.first.x, v.first.y).dy);
    final n = closed ? v.length : v.length - 1;
    for (var i = 0; i < n; i++) {
      final a = v[i], c = v[(i + 1) % v.length];
      final to = p(c.x, c.y);
      if (a.bulge == 0) {
        path.lineTo(to.dx, to.dy);
      } else {
        final chord = math.sqrt((c.x - a.x) * (c.x - a.x) + (c.y - a.y) * (c.y - a.y));
        final sweep = 4 * math.atan(a.bulge);
        final r = chord / (2 * math.sin(sweep.abs() / 2)) * k;
        // on screen y runs down, so the arc turns the other way
        path.arcToPoint(to, radius: Radius.circular(r), largeArc: sweep.abs() > math.pi, clockwise: sweep < 0);
      }
    }
    if (closed) path.close();
    return path;
  }

  @override
  bool shouldRepaint(_CadPainter old) =>
      old.d != d || old.hidden.length != hidden.length || !old.hidden.containsAll(hidden);
}
