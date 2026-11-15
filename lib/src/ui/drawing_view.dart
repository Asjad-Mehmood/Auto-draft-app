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
import '../engine/symbols.dart';
import '../state/app_state.dart';
import 'aci.dart';

class DrawingView extends StatefulWidget {
  const DrawingView({super.key, required this.state});
  final AppState state;

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

  Bounds? get _bounds => widget.state.drawing?.bounds;

  void _fit() {
    final b = _bounds;
    if (b == null || _size.isEmpty) return;
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
  Offset _toLocal(Vertex v) {
    final b = _bounds!;
    return Offset((v.e - b.minE) * _zoom, (b.maxN - v.n) * _zoom) + _pan;
  }

  (double, double) _toGround(Offset o) {
    final b = _bounds!;
    final p = o - _pan;
    return (b.minE + p.dx / _zoom, b.maxN - p.dy / _zoom);
  }

  void _zoomAt(Offset at, double factor) {
    final z = (_zoom * factor).clamp(1e-4, 1e4);
    final f = z / _zoom;
    setState(() {
      _pan = at - (at - _pan) * f;
      _zoom = z;
    });
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
                    child: MouseRegion(
                      cursor: SystemMouseCursors.precise,
                      onExit: (_) => setState(() => _pointer = null),
                      child: CustomPaint(
                        painter: d == null || _bounds == null
                            ? null
                            : _Painter(d, widget.state.hiddenLayers, _toLocal, _zoom, widget.state.focus.value),
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

class _Painter extends CustomPainter {
  _Painter(this.d, this.hidden, this.toLocal, this.zoom, this.focus);
  final Drawing d;
  final Set<String> hidden;
  final Offset Function(Vertex) toLocal;
  final double zoom;
  final FocusRequest? focus;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = BrandColors.canvas);
    final colors = {for (final l in d.layers) l.name: aciOnDark(l.color)};
    final screen = Offset.zero & size;

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
      _symbol(canvas, symbols[s.symbol] ?? symbols[unknownSymbol]!, c, symbolPx, colors[s.layer] ?? Colors.white);
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
  }

  void _symbol(Canvas canvas, SymbolDef def, Offset c, double px, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    Offset at(double x, double y) => c + Offset(x * px, -y * px);
    for (final part in def.parts) {
      switch (part) {
        case SLine(:final x1, :final y1, :final x2, :final y2):
          canvas.drawLine(at(x1, y1), at(x2, y2), paint);
        case SCircle(:final x, :final y, :final r):
          canvas.drawCircle(at(x, y), r * px, paint);
        case SPoly(:final xy, :final closed):
          final path = Path()..moveTo(at(xy[0], xy[1]).dx, at(xy[0], xy[1]).dy);
          for (var i = 2; i + 1 < xy.length; i += 2) {
            final p = at(xy[i], xy[i + 1]);
            path.lineTo(p.dx, p.dy);
          }
          if (closed) path.close();
          canvas.drawPath(path, paint);
      }
    }
  }

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
