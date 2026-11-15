// AutoCAD colour numbers (ACI) as red, green, blue: close to what AutoCAD shows. Plain Dart, for the
// PDF and the screen alike.
import 'dart:math' as math;

const _base = <int, (int, int, int)>{
  1: (255, 0, 0),
  2: (255, 255, 0),
  3: (0, 255, 0),
  4: (0, 255, 255),
  5: (0, 0, 255),
  6: (255, 0, 255),
  7: (255, 255, 255),
  8: (128, 128, 128),
  9: (192, 192, 192),
};

(int, int, int) aciRgb(int aci) {
  final c = _base[aci];
  if (c != null) return c;
  if (aci >= 250 && aci <= 255) {
    final v = (51 + (aci - 250) * 40.8).round().clamp(0, 255);
    return (v, v, v);
  }
  if (aci < 10 || aci > 249) return (255, 255, 255);
  // 10–249: 24 hues of 10 shades; even = full colour, odd = paler; brightness falls in pairs
  final hue = ((aci ~/ 10) - 1) * 15.0;
  final shade = aci % 10;
  const values = [1.0, 1.0, 0.8, 0.8, 0.6, 0.6, 0.5, 0.5, 0.3, 0.3];
  return _hsv(hue, shade.isEven ? 1.0 : 0.5, values[shade]);
}

(int, int, int) _hsv(double h, double s, double v) {
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
  return (ch(r), ch(g), ch(b));
}

/// For white paper: colour 7 prints black (as in AutoCAD), and very light colours (yellow) darker
(int, int, int) aciOnPaper(int aci) {
  if (aci == 7) return (0, 0, 0);
  final (r, g, b) = aciRgb(aci);
  final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  if (lum < 0.6) return (r, g, b);
  const k = 0.55; // towards black
  return ((r * k).round(), (g * k).round(), (b * k).round());
}
