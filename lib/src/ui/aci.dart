// AutoCAD colour numbers (ACI) as screen colours (lib/src/engine/aci.dart has the table).
import 'dart:ui';

import '../engine/aci.dart';

Color aciColor(int aci) {
  final (r, g, b) = aciRgb(aci);
  return Color.fromARGB(255, r, g, b);
}

/// Pure blue is hard to see on the dark drawing area: lighten very dark colours for the screen
/// (the DXF keeps the real number)
Color aciOnDark(int aci) {
  final c = aciColor(aci);
  final lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
  if (lum >= 0.25) return c;
  return Color.lerp(c, const Color(0xFFFFFFFF), 0.35)!;
}
