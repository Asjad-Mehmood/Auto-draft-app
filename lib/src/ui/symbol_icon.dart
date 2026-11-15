// A symbol drawn small, for the code list and the code editor (the same parts as in the DXF).
import 'package:flutter/material.dart';

import '../engine/symbols.dart';

class SymbolIcon extends StatelessWidget {
  const SymbolIcon(this.name, {super.key, this.size = 22, this.color = const Color(0xFF0E1B33)});
  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _SymbolPainter(symbols[name] ?? symbols[unknownSymbol]!, color));
}

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.def, this.color);
  final SymbolDef def;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => paintSymbol(canvas, def, size.center(Offset.zero), size.width * 0.9, color);

  @override
  bool shouldRepaint(_SymbolPainter old) => old.def != def || old.color != color;
}

/// Draws [def] centred on [c], [px] pixels wide
void paintSymbol(Canvas canvas, SymbolDef def, Offset c, double px, Color color, {double stroke = 1.3}) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke;
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
