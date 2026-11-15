// The symbols placed at point features (trees, poles, manholes…), drawn once here and used both
// for the DXF blocks and the on-screen preview, so the two always look the same. Each symbol is
// one drawing unit wide, centred on the point; the drawing scales it to the size on paper.

sealed class SymbolPart {
  const SymbolPart();
}

class SLine extends SymbolPart {
  const SLine(this.x1, this.y1, this.x2, this.y2);
  final double x1, y1, x2, y2;
}

class SCircle extends SymbolPart {
  const SCircle(this.x, this.y, this.r);
  final double x, y, r;
}

/// A closed or open polyline through the points [x0, y0, x1, y1, …]
class SPoly extends SymbolPart {
  const SPoly(this.xy, {this.closed = true});
  final List<double> xy;
  final bool closed;
}

class SymbolDef {
  const SymbolDef(this.name, this.label, this.parts);

  /// The block name in the DXF (letters, digits and _ only, for DXF R12)
  final String name;

  /// What people call it
  final String label;
  final List<SymbolPart> parts;
}

const _tree = SymbolDef('AD_TREE', 'Tree', [
  SCircle(0, 0, 0.5),
  SCircle(0, 0, 0.08),
  SLine(-0.5, 0, -0.25, 0),
  SLine(0.25, 0, 0.5, 0),
  SLine(0, -0.5, 0, -0.25),
  SLine(0, 0.25, 0, 0.5),
]);

const _pole = SymbolDef('AD_ELEC_POLE', 'Electric pole', [
  SCircle(0, 0, 0.35),
  SLine(-0.25, -0.25, 0.25, 0.25),
  SLine(-0.25, 0.25, 0.25, -0.25),
]);

const _telephone = SymbolDef('AD_TEL_POLE', 'Telephone pole', [
  SCircle(0, 0, 0.35),
  SLine(-0.2, 0.15, 0.2, 0.15),
  SLine(0, 0.15, 0, -0.22),
]);

const _light = SymbolDef('AD_LIGHT_POLE', 'Light pole', [
  SCircle(0, 0, 0.2),
  SLine(0.2, 0, 0.5, 0),
  SLine(-0.2, 0, -0.5, 0),
  SLine(0, 0.2, 0, 0.5),
  SLine(0, -0.2, 0, -0.5),
]);

const _transformer = SymbolDef('AD_TRANSFORMER', 'Transformer', [
  SPoly([-0.5, -0.3, 0.5, -0.3, 0.5, 0.3, -0.5, 0.3]),
  SLine(-0.5, -0.3, 0.5, 0.3),
  SLine(-0.5, 0.3, 0.5, -0.3),
]);

const _manhole = SymbolDef('AD_MANHOLE', 'Manhole', [
  SPoly([-0.4, -0.4, 0.4, -0.4, 0.4, 0.4, -0.4, 0.4]),
  SCircle(0, 0, 0.28),
]);

const _valve = SymbolDef('AD_VALVE', 'Valve', [
  SPoly([-0.45, -0.3, 0.45, 0.3, 0.45, -0.3, -0.45, 0.3]),
]);

const _handPump = SymbolDef('AD_HAND_PUMP', 'Hand pump', [
  SCircle(0, 0, 0.3),
  SLine(0, 0.3, 0, 0.55),
  SLine(-0.35, 0.55, 0.35, 0.45),
]);

const _tubewell = SymbolDef('AD_TUBEWELL', 'Tubewell', [SCircle(0, 0, 0.45), SCircle(0, 0, 0.22)]);

const _well = SymbolDef('AD_WELL', 'Well', [SCircle(0, 0, 0.45), SCircle(0, 0, 0.38)]);

const _benchmark = SymbolDef('AD_BENCHMARK', 'Benchmark', [
  SPoly([-0.45, -0.3, 0.45, -0.3, 0, 0.48]),
  SCircle(0, -0.02, 0.07),
]);

const _control = SymbolDef('AD_CONTROL', 'Control point', [
  SPoly([-0.45, -0.3, 0.45, -0.3, 0, 0.48]),
  SCircle(0, 0, 0.5),
]);

const _kmStone = SymbolDef('AD_KM_STONE', 'Kilometre stone', [
  SPoly([-0.3, -0.4, 0.3, -0.4, 0.3, 0.1, 0, 0.4, -0.3, 0.1]),
]);

const _sign = SymbolDef('AD_SIGN', 'Sign board', [
  SLine(0, -0.5, 0, 0.1),
  SPoly([-0.4, 0.1, 0.4, 0.1, 0.4, 0.5, -0.4, 0.5]),
]);

const _spot = SymbolDef('AD_SPOT', 'Spot level', [SLine(-0.25, -0.25, 0.25, 0.25), SLine(-0.25, 0.25, 0.25, -0.25)]);

const _unknown = SymbolDef('AD_UNKNOWN', 'Unknown code', [
  SPoly([-0.3, -0.3, 0.3, -0.3, 0.3, 0.3, -0.3, 0.3]),
]);

/// Every symbol, by its block name
const Map<String, SymbolDef> symbols = {
  'AD_TREE': _tree,
  'AD_ELEC_POLE': _pole,
  'AD_TEL_POLE': _telephone,
  'AD_LIGHT_POLE': _light,
  'AD_TRANSFORMER': _transformer,
  'AD_MANHOLE': _manhole,
  'AD_VALVE': _valve,
  'AD_HAND_PUMP': _handPump,
  'AD_TUBEWELL': _tubewell,
  'AD_WELL': _well,
  'AD_BENCHMARK': _benchmark,
  'AD_CONTROL': _control,
  'AD_KM_STONE': _kmStone,
  'AD_SIGN': _sign,
  'AD_SPOT': _spot,
  'AD_UNKNOWN': _unknown,
};

const unknownSymbol = 'AD_UNKNOWN';
