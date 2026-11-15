// AutoCAD colour numbers (ACI) as screen colours, close to what AutoCAD shows on a dark background.
import 'dart:math' as math;
import 'dart:ui';

const _base = <int, Color>{
  1: Color(0xFFFF0000),
  2: Color(0xFFFFFF00),
  3: Color(0xFF00FF00),
  4: Color(0xFF00FFFF),
  5: Color(0xFF0000FF),
  6: Color(0xFFFF00FF),
  7: Color(0xFFFFFFFF),
  8: Color(0xFF808080),
  9: Color(0xFFC0C0C0),
};

Color aciColor(int aci) {
  final c = _base[aci];
  if (c != null) return c;
  if (aci >= 250 && aci <= 255) {
    final v = (51 + (aci - 250) * 40.8).round().clamp(0, 255);
    return Color.fromARGB(255, v, v, v);
  }
  if (aci < 10 || aci > 249) return const Color(0xFFFFFFFF);
  // 10–249: 24 hues of 10 shades; even = full colour, odd = paler; brightness falls in pairs
  final hue = ((aci ~/ 10) - 1) * 15.0;
  final shade = aci % 10;
  const values = [1.0, 1.0, 0.8, 0.8, 0.6, 0.6, 0.5, 0.5, 0.3, 0.3];
  final sat = shade.isEven ? 1.0 : 0.5;
  return _hsv(hue, sat, values[shade]);
}

Color _hsv(double h, double s, double v) {
  final c = v * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = v - c;
  final (r, g, b) = switch (h) {
    < 60 => (c, x, 0.0),
    < 120 => (x, c, 0.0),
    < 180 => (0.0, c, x),
    < 240 => (0.0, x, c),
    < 300 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  int ch(double t) => math.min(255, ((t + m) * 255).round());
  return Color.fromARGB(255, ch(r), ch(g), ch(b));
}

/// Pure blue is hard to see on the dark drawing area: lighten very dark colours for the screen
/// (the DXF keeps the real number)
Color aciOnDark(int aci) {
  final c = aciColor(aci);
  final lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
  if (lum >= 0.25) return c;
  return Color.lerp(c, const Color(0xFFFFFFFF), 0.35)!;
}
