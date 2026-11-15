// The code list: what each field code means and how it is drawn. A line code joins its points
// into a line (road edge, wall, drain); a point code places a symbol (tree, pole, manhole).
// The defaults follow common topographic survey practice; every code can be renamed, added or
// removed, and a list can be saved to a file and shared with the team (codes.json).
import 'dart:convert';

import 'symbols.dart';

enum CodeKind { line, point }

/// The line types the drawing defines (DXF R12 names)
const lineTypes = ['CONTINUOUS', 'DASHED', 'HIDDEN', 'CENTER', 'DASHDOT', 'DOT'];

class FeatureCode {
  const FeatureCode({
    required this.code,
    required this.name,
    required this.kind,
    required this.layer,
    this.color = 7,
    this.lineType = 'CONTINUOUS',
    this.symbol = '',
    this.levels = true,
  });

  /// What the surveyor types: "RE"
  final String code;

  /// What it is: "Road edge"
  final String name;
  final CodeKind kind;

  /// The layer it is drawn on: "ROAD_EDGE"
  final String layer;

  /// AutoCAD colour number (1 red, 2 yellow, 3 green, 4 cyan, 5 blue, 6 magenta, 7 white/black…)
  final int color;
  final String lineType;

  /// For point codes: the symbol's block name (symbols.dart)
  final String symbol;

  /// Whether its points get their level written beside them
  final bool levels;

  Map<String, Object> toJson() => {
    'code': code,
    'name': name,
    'kind': kind.name,
    'layer': layer,
    'color': color,
    'lineType': lineType,
    if (symbol.isNotEmpty) 'symbol': symbol,
    'levels': levels,
  };

  static FeatureCode? fromJson(Object? j) {
    if (j is! Map) return null;
    final code = j['code'], name = j['name'], kind = j['kind'], layer = j['layer'];
    if (code is! String || name is! String || kind is! String || layer is! String) return null;
    final k = CodeKind.values.where((v) => v.name == kind).firstOrNull;
    if (k == null || !validCode(code) || !validLayer(layer)) return null;
    final color = j['color'], lt = j['lineType'], sym = j['symbol'], lv = j['levels'];
    return FeatureCode(
      code: code.toUpperCase(),
      name: name,
      kind: k,
      layer: layer.toUpperCase(),
      color: color is int && color >= 1 && color <= 255 ? color : 7,
      lineType: lt is String && lineTypes.contains(lt) ? lt : 'CONTINUOUS',
      symbol: sym is String && symbols.containsKey(sym) ? sym : (k == CodeKind.point ? unknownSymbol : ''),
      levels: lv is bool ? lv : true,
    );
  }
}

/// A code is letters, then optionally more letters or digits: "RE", "BLD", "TB2X"
bool validCode(String c) => RegExp(r'^[A-Za-z][A-Za-z0-9]{0,11}$').hasMatch(c) && !isControlWord(c.toUpperCase());

/// DXF R12 layer names: letters, digits, _ - and $, up to 31 characters
bool validLayer(String l) => RegExp(r'^[A-Za-z0-9_\-$]{1,31}$').hasMatch(l);

/// The words that steer a line rather than name a feature (see the user guide)
enum Control {
  /// start a new line here
  start,

  /// this is the line's last point
  end,

  /// close the shape back to its first point
  close,

  /// a curve starts at this point
  arc,

  /// the curve ends at this point
  endArc,

  /// this is the third corner of a rectangle: the fourth is added and the shape closed
  rect,
}

const controlWords = <String, Control>{
  'ST': Control.start,
  'START': Control.start,
  'END': Control.end,
  'CLS': Control.close,
  'CLOSE': Control.close,
  'ARC': Control.arc,
  'EARC': Control.endArc,
  'ENDARC': Control.endArc,
  'RECT': Control.rect,
};

bool isControlWord(String w) => controlWords.containsKey(w);

class CodeLibrary {
  CodeLibrary(Iterable<FeatureCode> codes) : _codes = {for (final c in codes) c.code.toUpperCase(): c};

  final Map<String, FeatureCode> _codes;

  List<FeatureCode> get all => _codes.values.toList()..sort((a, b) => a.code.compareTo(b.code));

  FeatureCode? operator [](String code) => _codes[code.toUpperCase()];

  bool contains(String code) => _codes.containsKey(code.toUpperCase());

  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert({'format': 'auto-draft-codes', 'version': 1, 'codes': all});

  /// Reads a saved code list; null when the text isn't one
  static CodeLibrary? fromJsonString(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['format'] != 'auto-draft-codes' || j['codes'] is! List) return null;
      final codes = [for (final c in j['codes'] as List) ?FeatureCode.fromJson(c)];
      return codes.isEmpty ? null : CodeLibrary(codes);
    } on FormatException {
      return null;
    }
  }

  static CodeLibrary defaults() => CodeLibrary(defaultCodes);
}

FeatureCode _line(String code, String name, String layer, int color, [String lt = 'CONTINUOUS']) =>
    FeatureCode(code: code, name: name, kind: CodeKind.line, layer: layer, color: color, lineType: lt);

FeatureCode _point(String code, String name, String layer, int color, String symbol, {bool levels = true}) =>
    FeatureCode(
      code: code,
      name: name,
      kind: CodeKind.point,
      layer: layer,
      color: color,
      symbol: symbol,
      levels: levels,
    );

/// The codes a new copy starts with
final defaultCodes = <FeatureCode>[
  // roads
  _line('RE', 'Road edge', 'ROAD_EDGE', 1),
  _line('EP', 'Edge of pavement', 'PAVEMENT_EDGE', 1),
  _line('KB', 'Kerb', 'KERB', 30),
  _line('SH', 'Shoulder', 'SHOULDER', 40, 'DASHED'),
  _line('CL', 'Centre line', 'CENTRE_LINE', 6, 'CENTER'),
  _line('FP', 'Footpath', 'FOOTPATH', 8),
  _line('TRK', 'Track / kacha road', 'TRACK', 42, 'DASHED'),
  _line('RLY', 'Railway', 'RAILWAY', 8, 'DASHDOT'),
  // buildings and boundaries
  _line('BLD', 'Building', 'BUILDING', 140),
  _line('WL', 'Wall', 'WALL', 7),
  _line('FN', 'Fence', 'FENCE', 3, 'DASHED'),
  _line('GT', 'Gate', 'GATE', 30),
  _line('PB', 'Plot boundary', 'PLOT_BOUNDARY', 6, 'DASHDOT'),
  // water and drainage
  _line('DR', 'Drain', 'DRAIN', 4),
  _line('NL', 'Nala / canal edge', 'NALA', 4),
  _line('WE', 'Water edge (pond)', 'WATER_EDGE', 4, 'DASHED'),
  _line('CV', 'Culvert / bridge', 'CULVERT', 150),
  _line('PIPE', 'Pipe line', 'PIPE', 4, 'HIDDEN'),
  // ground shape
  _line('TB', 'Top of bank', 'TOP_OF_BANK', 2),
  _line('BB', 'Bottom of bank (toe)', 'TOE_OF_BANK', 2, 'DASHED'),
  _line('HT', 'Overhead power line', 'POWER_LINE', 1, 'DASHDOT'),
  // points
  _point('TR', 'Tree', 'TREE', 3, 'AD_TREE'),
  _point('EPL', 'Electric pole', 'ELECTRIC_POLE', 1, 'AD_ELEC_POLE'),
  _point('TP', 'Telephone pole', 'TELEPHONE_POLE', 30, 'AD_TEL_POLE'),
  _point('LP', 'Light pole', 'LIGHT_POLE', 2, 'AD_LIGHT_POLE'),
  _point('TF', 'Transformer', 'TRANSFORMER', 1, 'AD_TRANSFORMER'),
  _point('MH', 'Manhole', 'MANHOLE', 4, 'AD_MANHOLE'),
  _point('VLV', 'Valve', 'VALVE', 4, 'AD_VALVE'),
  _point('HP', 'Hand pump', 'HAND_PUMP', 4, 'AD_HAND_PUMP'),
  _point('TW', 'Tubewell', 'TUBEWELL', 4, 'AD_TUBEWELL'),
  _point('WEL', 'Well', 'WELL', 4, 'AD_WELL'),
  _point('BM', 'Benchmark', 'BENCHMARK', 6, 'AD_BENCHMARK'),
  _point('TBM', 'Temporary benchmark', 'BENCHMARK', 6, 'AD_BENCHMARK'),
  _point('CP', 'Control point / station', 'CONTROL', 6, 'AD_CONTROL'),
  _point('KM', 'Kilometre stone', 'KM_STONE', 7, 'AD_KM_STONE'),
  _point('SB', 'Sign board', 'SIGN', 2, 'AD_SIGN'),
  _point('SP', 'Spot level', 'SPOT_LEVEL', 8, 'AD_SPOT'),
  _point('NGL', 'Natural ground level', 'SPOT_LEVEL', 8, 'AD_SPOT'),
];
