// The drawing on screen, dark as in a CAD program. The mouse wheel zooms at the pointer, dragging
// moves it, a double click fits the whole drawing. Text appears once it is big enough to read.
// A problem or point picked in the side panel is zoomed to and ringed in gold.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../brand.dart';
import '../engine/drawing.dart';
import '../engine/geometry.dart';
import '../engine/point.dart';
import '../engine/sheet.dart';
import '../engine/symbols.dart';
import '../state/app_state.dart';
import 'aci.dart';
import 'symbol_icon.dart';
import 'theme.dart';

class DrawingView extends StatefulWidget {
  const DrawingView({super.key, required this.state, this.onEditPoint});
  final AppState state;

  /// "Change code" on the picked point's card
  final void Function(int index)? onEditPoint;

  @override
  State<DrawingView> createState() => _DrawingViewState();
}

class _DrawingViewState extends State<DrawingView> {
  /// Pixels per metre, and the screen position of the drawing's origin (min E, max N)
  double _zoom = 1;
  Offset _pan = Offset.zero;
  Size _size = Size.zero;
  int _generation = -1;
  Offset? _pointer;

  @override
  void initState() {
    super.initState();
    widget.state.focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(DrawingView old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      old.state.focus.removeListener(_onFocus);
      widget.state.focus.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.state.focus.removeListener(_onFocus);
    super.dispose();
  }

  /// What is shown: the survey, and the sheet round it when it is on
  Bounds? get _bounds {
    final b = widget.state.drawing?.bounds;
    final sh = widget.state.showSheet ? widget.state.sheet!.bounds : null;
    if (b == null || sh == null) return b;
    return Bounds(
      math.min(b.minE, sh.minE),
      math.min(b.minN, sh.minN),
      math.max(b.maxE, sh.maxE),
      math.max(b.maxN, sh.maxN),
      b.minZ,
      b.maxZ,
    );
  }

  /// The ground point at the view's top left, fixed when the view is fitted
  double _refE = 0, _refN = 0;

  void _fit() {
    final b = _bounds;
    if (b == null || _size.isEmpty) return;
    _refE = b.minE;
    _refN = b.maxN;
    final w = math.max(b.width, 1.0), h = math.max(b.height, 1.0);
    _zoom = math.min((_size.width - 80) / w, (_size.height - 80) / h).clamp(1e-4, 1e4);
    _pan = Offset((_size.width - w * _zoom) / 2, (_size.height - h * _zoom) / 2);
  }

  void _onFocus() {
    final f = widget.state.focus.value;
    if (f == null || _bounds == null) return;
    setState(() {
      // close enough to read the text around it
      final want = math.max(_zoom, 12 / math.max(widget.state.options.textHeight, 0.01));
      _zoom = want.clamp(1e-4, 1e4);
      final p = _toLocal(f.at);
      _pan += Offset(_size.width / 2, _size.height / 2) - p;
    });
  }

  /// Ground → screen. The drawing's origin is its top-left corner (min E, max N).
  Offset _toLocal(Vertex v) => Offset((v.e - _refE) * _zoom, (_refN - v.n) * _zoom) + _pan;

  (double, double) _toGround(Offset o) {
    final p = o - _pan;
    return (_refE + p.dx / _zoom, _refN - p.dy / _zoom);
  }

  void _zoomAt(Offset at, double factor) {
    final z = (_zoom * factor).clamp(1e-4, 1e4);
    final f = z / _zoom;
    setState(() {
      _pan = at - (at - _pan) * f;
      _zoom = z;
    });
  }

  /// The point nearest a click, within 14 pixels; a click away from every point clears the pick
  void _pickAt(Offset at) {
    final pts = widget.state.points;
    if (_bounds == null) return;
    int? best;
    var bestD = 14.0 * 14.0;
    for (var i = 0; i < pts.length; i++) {
      final d2 = (_toLocal(Vertex(pts[i].e, pts[i].n)) - at).distanceSquared;
      if (d2 <= bestD) {
        bestD = d2;
        best = i;
      }
    }
    widget.state.pick(best);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.state.drawing;
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        // a newly opened survey is fitted to the window; a redraw of the same one keeps the view
        final gen = widget.state.fileGeneration;
        final refit = _size.isEmpty || gen != _generation;
        _size = size;
        if (refit && d != null) {
          _fit();
          _generation = gen;
        }
        final ground = _pointer == null || d == null || _bounds == null ? null : _toGround(_pointer!);
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerSignal: (e) {
                    if (e is PointerScrollEvent && _bounds != null) {
                      _zoomAt(e.localPosition, e.scrollDelta.dy < 0 ? 1.2 : 1 / 1.2);
                    }
                  },
                  onPointerHover: (e) => setState(() => _pointer = e.localPosition),
                  child: GestureDetector(
                    onPanUpdate: (e) => setState(() => _pan += e.delta),
                    onDoubleTap: () => setState(_fit),
                    onTapUp: (e) => _pickAt(e.localPosition),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.precise,
                      onExit: (_) => setState(() => _pointer = null),
                      child: CustomPaint(
                        painter: d == null || _bounds == null
                            ? null
                            : _Painter(
                                d,
                                widget.state.hiddenLayers,
                                _toLocal,
                                _zoom,
                                widget.state.focus.value,
                                widget.state.picked,
                                widget.state.showSheet ? widget.state.sheet : null,
                              ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
              // the zoom buttons and the pointer's coordinates
              Positioned(
                right: 12,
                top: 12,
                child: Column(
                  children: [
                    _ZoomButton(Icons.add, 'Zoom in', () => _zoomAt(Offset(_size.width / 2, _size.height / 2), 1.5)),
                    const SizedBox(height: 6),
                    _ZoomButton(
                      Icons.remove,
                      'Zoom out',
                      () => _zoomAt(Offset(_size.width / 2, _size.height / 2), 1 / 1.5),
                    ),
                    const SizedBox(height: 6),
                    _ZoomButton(
                      Icons.fit_screen_outlined,
                      'Fit the whole drawing (or double-click)',
                      () => setState(_fit),
                    ),
                  ],
                ),
              ),
              if (widget.state.picked != null && widget.state.picked! < widget.state.points.length)
                Positioned(
                  left: 12,
                  bottom: 34,
                  child: _PointCard(
                    state: widget.state,
                    index: widget.state.picked!,
                    onEdit: widget.onEditPoint == null ? null : () => widget.onEditPoint!(widget.state.picked!),
                  ),
                ),
              if (ground != null)
                Positioned(
                  left: 12,
                  bottom: 10,
                  child: Text(
                    'E ${ground.$1.toStringAsFixed(3)}   N ${ground.$2.toStringAsFixed(3)}',
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12, color: Color(0xFFB8C4D8)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton(this.icon, this.tip, this.onTap);
  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: Material(
      color: const Color(0xFF17243A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF2A3B57)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(width: 36, height: 36, child: Icon(icon, size: 19, color: const Color(0xFFDCE4F2))),
      ),
    ),
  );
}

class _PointCard extends StatelessWidget {
  const _PointCard({required this.state, required this.index, this.onEdit});
  final AppState state;
  final int index;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final p = state.points[index];
    final was = state.fileCodeOf(index);
    const label = TextStyle(color: Color(0xFF8FA0BC), fontSize: 11.5);
    final value = mono.copyWith(color: Colors.white, fontSize: 12.5);
    return Material(
      color: const Color(0xF2121D31),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF2A3B57)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Point ${p.id}',
                  style: const TextStyle(color: BrandColors.goldLight, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Code ', style: label),
                    Text(p.code.isEmpty ? '(none)' : p.code, style: value.copyWith(fontWeight: FontWeight.w700)),
                    if (was != null) Text('   was ${was.isEmpty ? '(none)' : was}', style: label),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'E ${p.e.toStringAsFixed(3)}  N ${p.n.toStringAsFixed(3)}  Z ${p.z?.toStringAsFixed(3) ?? '—'}',
                  style: value,
                ),
              ],
            ),
            const SizedBox(width: 10),
            if (onEdit != null)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: BrandColors.goldLight),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Change code'),
              ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close, size: 18, color: Color(0xFFB8C4D8)),
              onPressed: () => state.pick(null),
            ),
          ],
        ),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.d, this.hidden, this.toLocal, this.zoom, this.focus, this.picked, this.sheet);
  final Sheet? sheet;
  final Drawing d;
  final Set<String> hidden;
  final Offset Function(Vertex) toLocal;
  final double zoom;
  final FocusRequest? focus;
  final int? picked;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = BrandColors.canvas);
    final colors = {for (final l in d.layers) l.name: aciOnDark(l.color)};
    final screen = Offset.zero & size;

    // the paper, a shade lighter than the background
    final sh = sheet;
    if (sh != null) {
      final b = sh.bounds;
      canvas.drawRect(
        Rect.fromPoints(toLocal(Vertex(b.minE, b.maxN)), toLocal(Vertex(b.maxE, b.minN))),
        Paint()..color = const Color(0xFF121C2F),
      );
    }

    // lines
    for (final l in d.lines) {
      if (hidden.contains(l.layer)) continue;
      final path = Path();
      for (var i = 0; i < l.vertices.length; i++) {
        final p = toLocal(l.vertices[i]);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      if (l.closed) path.close();
      if (!path.getBounds().inflate(4).overlaps(screen)) continue;
      final paint = Paint()
        ..color = colors[l.layer] ?? Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round;
      if (l.feature.lineType == 'CONTINUOUS') {
        canvas.drawPath(path, paint);
      } else {
        _dashed(canvas, path, paint, l.feature.lineType);
      }
    }

    // symbols, at their size on paper (and never smaller than 7 pixels, so they show when zoomed out)
    final symbolPx = math.max(d.options.symbolSize * zoom, 7.0);
    for (final s in d.symbols) {
      if (hidden.contains(s.layer)) continue;
      final c = toLocal(s.at);
      if (!screen.inflate(symbolPx).contains(c)) continue;
      paintSymbol(canvas, symbols[s.symbol] ?? symbols[unknownSymbol]!, c, symbolPx, colors[s.layer] ?? Colors.white);
    }

    // point markers
    if (!hidden.contains(Layers.points.name)) {
      final dot = Paint()..color = const Color(0xFF9FB0CC);
      for (final p in d.points) {
        final c = toLocal(Vertex(p.e, p.n));
        if (screen.contains(c)) canvas.drawCircle(c, 1.6, dot);
      }
    }

    // text, once it is at least 7 pixels high
    final textPx = d.options.textHeight * zoom;
    if (textPx >= 7) {
      for (final t in d.texts) {
        if (hidden.contains(t.layer)) continue;
        final base = toLocal(t.at);
        if (!screen.inflate(200).contains(base)) continue;
        final h = t.height * zoom;
        final tp = TextPainter(
          text: TextSpan(
            text: t.text,
            style: TextStyle(
              color: colors[t.layer] ?? Colors.white,
              fontSize: h * 1.25,
              height: 1,
              fontFamily: 'Inter',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // the DXF text sits on its baseline; Flutter draws from the top
        tp.paint(canvas, base - Offset(0, tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
      }
    }

    if (sh != null) _paintSheet(canvas, sh, screen);

    // the picked problem or point
    final f = focus;
    if (f != null) {
      final ring = Paint()
        ..color = BrandColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      final ids = f.pointIds.toSet();
      var any = false;
      for (final p in d.points.where((p) => ids.contains(p.id))) {
        canvas.drawCircle(toLocal(Vertex(p.e, p.n)), math.max(12, symbolPx * 0.9), ring);
        any = true;
      }
      if (!any) canvas.drawCircle(toLocal(f.at), 16, ring);
    }

    // the point clicked: a gold cross-hair
    final k = picked;
    if (k != null && k < d.points.length) {
      final c = toLocal(Vertex(d.points[k].e, d.points[k].n));
      final gold = Paint()
        ..color = BrandColors.goldLight
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(c, 9, gold);
      for (final dir in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
        canvas.drawLine(c + dir * 5, c + dir * 16, gold);
      }
    }
  }

  void _paintSheet(Canvas canvas, Sheet sh, Rect screen) {
    final mmPx = sh.f * zoom; // pixels per mm on paper
    for (final item in sh.items) {
      switch (item) {
        case SheetPolyline(:final layer, :final points, :final closed, :final color, :final lineType, :final weightMm):
          final path = Path();
          for (var i = 0; i < points.length; i++) {
            final p = toLocal(points[i]);
            i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
          }
          if (closed) path.close();
          final paint = Paint()
            ..color = aciOnDark(color ?? _sheetColor(layer))
            ..style = PaintingStyle.stroke
            ..strokeWidth = (weightMm * mmPx).clamp(0.6, 3.0);
          if (lineType == null || lineType == 'CONTINUOUS') {
            canvas.drawPath(path, paint);
          } else {
            _dashed(canvas, path, paint, lineType);
          }
        case SheetSolid(:final layer, :final corners):
          final path = Path();
          for (var i = 0; i < corners.length; i++) {
            final p = toLocal(corners[i]);
            i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
          }
          canvas.drawPath(path..close(), Paint()..color = aciOnDark(_sheetColor(layer)));
        case SheetSymbol(:final layer, :final symbol, :final at, :final size, :final color):
          paintSymbol(
            canvas,
            symbols[symbol] ?? symbols[unknownSymbol]!,
            toLocal(at),
            size * zoom,
            aciOnDark(color ?? _sheetColor(layer)),
          );
        case SheetText(:final layer, :final text, :final at, :final height, :final align, :final rotation, :final bold):
          final h = height * zoom;
          if (h < 4) continue;
          final base = toLocal(at);
          if (!screen.inflate(400).contains(base)) continue;
          final tp = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                color: aciOnDark(_sheetColor(layer)),
                fontSize: h * 1.38,
                height: 1,
                fontFamily: 'Inter',
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final dx = switch (align) {
            SheetAlign.left => 0.0,
            SheetAlign.center => -tp.width / 2,
            SheetAlign.right => -tp.width,
          };
          canvas.save();
          canvas.translate(base.dx, base.dy);
          canvas.rotate(-rotation * math.pi / 180);
          tp.paint(canvas, Offset(dx, -tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
          canvas.restore();
      }
    }
  }

  int _sheetColor(String name) => SheetLayers.all.where((l) => l.name == name).firstOrNull?.color ?? 7;

  /// Line types on screen, at a fixed size in pixels
  void _dashed(Canvas canvas, Path path, Paint paint, String type) {
    final pattern = switch (type) {
      'DASHED' => [10.0, 6.0],
      'HIDDEN' => [5.0, 4.0],
      'CENTER' => [18.0, 4.0, 4.0, 4.0],
      'DASHDOT' => [10.0, 4.0, 1.5, 4.0],
      'DOT' => [1.5, 4.0],
      _ => [1.0, 0.0],
    };
    for (final m in path.computeMetrics()) {
      var dist = 0.0, i = 0;
      while (dist < m.length) {
        final len = pattern[i % pattern.length];
        if (i.isEven) canvas.drawPath(m.extractPath(dist, math.min(dist + len, m.length)), paint);
        dist += len;
        i++;
      }
    }
  }

  @override
  bool shouldRepaint(_Painter old) => true;
}
