// A CAD drawing rebuilt from a PDF: layers, line types, text styles and the objects on them, in
// drawing units (millimetres on paper, or metres at the chosen scale). The DXF writer and the
// preview draw from this.
import 'dart:math' as math;

/// A vertex of a polyline; [bulge] curves the piece to the next vertex (tan of a quarter of its angle)
class CadVertex {
  const CadVertex(this.x, this.y, [this.bulge = 0]);
  final double x, y, bulge;
  CadVertex withBulge(double b) => CadVertex(x, y, b);
}

/// The look shared by every object: layer, colour, line type and lineweight
class CadStyle {
  const CadStyle({
    required this.layer,
    this.aci = 256,
    this.lineType = 'BYLAYER',
    this.ltScale = 1,
    this.lineWeight = -1,
  });
  final String layer;

  /// 256: as the layer
  final int aci;

  /// BYLAYER, or a line type's name
  final String lineType;
  final double ltScale;

  /// hundredths of a mm; -1: as the layer
  final int lineWeight;

  CadStyle copyWith({String? layer, int? aci, String? lineType, double? ltScale, int? lineWeight}) => CadStyle(
    layer: layer ?? this.layer,
    aci: aci ?? this.aci,
    lineType: lineType ?? this.lineType,
    ltScale: ltScale ?? this.ltScale,
    lineWeight: lineWeight ?? this.lineWeight,
  );
}

sealed class CadEntity {
  CadEntity(this.style);
  CadStyle style;
}

class CadLine extends CadEntity {
  CadLine(super.style, this.x1, this.y1, this.x2, this.y2);
  final double x1, y1, x2, y2;
}

class CadPolyline extends CadEntity {
  CadPolyline(super.style, this.vertices, {required this.closed});
  final List<CadVertex> vertices;
  final bool closed;
}

class CadCircle extends CadEntity {
  CadCircle(super.style, this.cx, this.cy, this.r);
  final double cx, cy, r;
}

/// Angles in degrees, anticlockwise from [start] to [end]
class CadArc extends CadEntity {
  CadArc(super.style, this.cx, this.cy, this.r, this.start, this.end);
  final double cx, cy, r, start, end;
}

class CadText extends CadEntity {
  CadText(super.style, this.text, this.x, this.y, this.height, this.angle, this.textStyle);
  final String text;
  final double x, y, height;

  /// degrees
  final double angle;
  final String textStyle;
}

/// A hatch: SOLID, or a pattern line family (angle in degrees, spacing in drawing units)
class CadHatch extends CadEntity {
  CadHatch(super.style, this.loops, {this.pattern = 'SOLID', this.angle = 0, this.spacing = 0, this.patternScale = 1});
  final List<List<CadVertex>> loops;
  final String pattern;
  final double angle, spacing, patternScale;
  bool get solid => pattern == 'SOLID';
}

/// A linear dimension: what it measures ([x1],[y1] → [x2],[y2]), where its line sits, and its text
class CadDimension extends CadEntity {
  CadDimension(
    super.style, {
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.lineX,
    required this.lineY,
    required this.textX,
    required this.textY,
    required this.angle,
    required this.text,
    required this.measured,
    required this.textHeight,
    required this.arrowSize,
    required this.block,
  });
  final double x1, y1, x2, y2;

  /// a point on the dimension line
  final double lineX, lineY;

  /// the middle of the text
  final double textX, textY;

  /// direction of the dimension line, degrees
  final double angle;

  /// as printed ("20.00"); empty when it shows the measurement
  final String text;
  final double measured;
  final double textHeight, arrowSize;

  /// what it looks like: the lines, arrows and text as drawn
  final List<CadEntity> block;
}

class CadLayer {
  CadLayer(this.name, {this.aci = 7, this.lineType = 'CONTINUOUS', this.lineWeight = -3});
  final String name;
  int aci;
  String lineType;

  /// hundredths of a mm; -3: default
  int lineWeight;
}

/// The standard AutoCAD line types (acadiso.lin, millimetres): dash > 0, gap < 0, dot 0
const standardLineTypes = <String, (String, List<double>)>{
  'CONTINUOUS': ('Solid line', []),
  'DASHED': ('Dashed __ __ __ __', [12.7, -6.35]),
  'HIDDEN': ('Hidden _ _ _ _ _', [6.35, -3.175]),
  'CENTER': ('Center ____ _ ____ _', [31.75, -6.35, 6.35, -6.35]),
  'PHANTOM': ('Phantom ____ _ _ ____', [31.75, -6.35, 6.35, -6.35, 6.35, -6.35]),
  'DOT': ('Dot . . . . . . . .', [0, -6.35]),
  'DASHDOT': ('Dash dot __ . __ . __', [12.7, -6.35, 0, -6.35]),
  'DIVIDE': ('Divide ____ . . ____', [12.7, -6.35, 0, -6.35, 0, -6.35]),
  'BORDER': ('Border __ __ . __ __ .', [12.7, -6.35, 12.7, -6.35, 0, -6.35]),
};

double standardPeriod(String lineType) =>
    (standardLineTypes[lineType]?.$2 ?? const []).fold(0.0, (a, b) => a + b.abs());

/// The standard lineweights, hundredths of a mm
const standardLineWeights = [
  0,
  5,
  9,
  13,
  15,
  18,
  20,
  25,
  30,
  35,
  40,
  50,
  53,
  60,
  70,
  80,
  90,
  100,
  106,
  120,
  140,
  158,
  200,
  211,
];

int nearestLineWeight(double mm) {
  final v = mm * 100;
  var best = standardLineWeights.first;
  for (final w in standardLineWeights) {
    if ((w - v).abs() < (best - v).abs()) best = w;
  }
  return best;
}

class CadDrawing {
  CadDrawing({required this.units, required this.scale});

  /// 'mm' (paper size) or 'm' (at [scale])
  final String units;

  /// 1:scale, when [units] is metres; 1 for paper millimetres
  final int scale;
  final layers = <String, CadLayer>{};
  final entities = <CadEntity>[];

  /// text style name → font file
  final textStyles = <String, String>{'Standard': 'arial.ttf'};

  /// what the reader noticed, for the person (pictures, text drawn as lines …)
  final notes = <String>[];

  CadLayer layer(String name, {int aci = 7}) => layers.putIfAbsent(name, () => CadLayer(name, aci: aci));

  ({double minX, double minY, double maxX, double maxY})? get bounds {
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    void add(double x, double y) {
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }

    void each(CadEntity e) {
      switch (e) {
        case CadLine():
          add(e.x1, e.y1);
          add(e.x2, e.y2);
        case CadPolyline():
          for (final v in e.vertices) {
            add(v.x, v.y);
          }
        case CadCircle():
          add(e.cx - e.r, e.cy - e.r);
          add(e.cx + e.r, e.cy + e.r);
        case CadArc():
          add(e.cx - e.r, e.cy - e.r);
          add(e.cx + e.r, e.cy + e.r);
        case CadText():
          add(e.x, e.y);
        case CadHatch():
          for (final l in e.loops) {
            for (final v in l) {
              add(v.x, v.y);
            }
          }
        case CadDimension():
          add(e.x1, e.y1);
          add(e.x2, e.y2);
          add(e.lineX, e.lineY);
      }
    }

    entities.forEach(each);
    if (minX == double.infinity) return null;
    return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  /// How many of each kind, for the summary
  Map<String, int> get counts {
    final out = <String, int>{};
    for (final e in entities) {
      final k = switch (e) {
        CadLine() => 'lines',
        CadPolyline() => 'polylines',
        CadCircle() => 'circles',
        CadArc() => 'arcs',
        CadText() => 'texts',
        CadHatch() => 'hatches',
        CadDimension() => 'dimensions',
      };
      out[k] = (out[k] ?? 0) + 1;
    }
    return out;
  }
}
