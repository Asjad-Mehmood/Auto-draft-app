// What the builder makes from the points: lines, symbols, text and the problems it found. The
// DXF writer and the on-screen preview both draw from this.
import 'codes.dart';
import 'contours.dart';
import 'geometry.dart';
import 'point.dart';
import 'tin.dart';

/// How the drawing is set out. Sizes are millimetres on paper; the scale turns them into metres.
class DraftOptions {
  const DraftOptions({
    this.scale = 500,
    this.textMm = 1.8,
    this.symbolMm = 3.0,
    this.levelDecimals = 3,
    this.levels = true,
    this.pointNumbers = false,
    this.codes = false,
    this.lines3d = false,
    this.contours = false,
    this.contourInterval = 0,
    this.majorEvery = 5,
    this.showTin = false,
  });

  /// 500 means 1:500
  final int scale;
  final double textMm;
  final double symbolMm;
  final int levelDecimals;

  /// Write each point's level beside it
  final bool levels;

  /// Write each point's number beside it
  final bool pointNumbers;

  /// Write each point's code beside it
  final bool codes;

  /// Lines as 3D polylines at the surveyed levels (for Civil 3D surfaces); otherwise flat
  final bool lines3d;

  /// Draw contours from the ground surface (TIN)
  final bool contours;

  /// Metres between contours; 0: chosen from the height range
  final double contourInterval;

  /// Every n-th contour is a major one, thicker and labelled
  final int majorEvery;

  /// Show the TIN's triangles too
  final bool showTin;

  static const intervals = [0.1, 0.2, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0];

  /// Text height in metres on the ground
  double get textHeight => textMm * scale / 1000;

  /// Symbol size in metres on the ground
  double get symbolSize => symbolMm * scale / 1000;

  static const scales = [100, 200, 250, 500, 1000, 1250, 2000, 2500, 5000];

  DraftOptions copyWith({
    int? scale,
    double? textMm,
    double? symbolMm,
    int? levelDecimals,
    bool? levels,
    bool? pointNumbers,
    bool? codes,
    bool? lines3d,
    bool? contours,
    double? contourInterval,
    int? majorEvery,
    bool? showTin,
  }) => DraftOptions(
    scale: scale ?? this.scale,
    textMm: textMm ?? this.textMm,
    symbolMm: symbolMm ?? this.symbolMm,
    levelDecimals: levelDecimals ?? this.levelDecimals,
    levels: levels ?? this.levels,
    pointNumbers: pointNumbers ?? this.pointNumbers,
    codes: codes ?? this.codes,
    lines3d: lines3d ?? this.lines3d,
    contours: contours ?? this.contours,
    contourInterval: contourInterval ?? this.contourInterval,
    majorEvery: majorEvery ?? this.majorEvery,
    showTin: showTin ?? this.showTin,
  );

  Map<String, Object> toJson() => {
    'scale': scale,
    'textMm': textMm,
    'symbolMm': symbolMm,
    'levelDecimals': levelDecimals,
    'levels': levels,
    'pointNumbers': pointNumbers,
    'codes': codes,
    'lines3d': lines3d,
    'contours': contours,
    'contourInterval': contourInterval,
    'majorEvery': majorEvery,
    'showTin': showTin,
  };

  static DraftOptions fromJson(Object? j) {
    const d = DraftOptions();
    if (j is! Map) return d;
    T pick<T>(String k, T fallback, [bool Function(T)? ok]) {
      final v = j[k];
      return v is T && (ok == null || ok(v)) ? v : fallback;
    }

    double mm(String k, double fallback) {
      final v = j[k];
      return v is num && v > 0 && v <= 20 ? v.toDouble() : fallback;
    }

    return DraftOptions(
      scale: pick<int>('scale', d.scale, (v) => v >= 1 && v <= 100000),
      textMm: mm('textMm', d.textMm),
      symbolMm: mm('symbolMm', d.symbolMm),
      levelDecimals: pick<int>('levelDecimals', d.levelDecimals, (v) => v >= 0 && v <= 4),
      levels: pick<bool>('levels', d.levels),
      pointNumbers: pick<bool>('pointNumbers', d.pointNumbers),
      codes: pick<bool>('codes', d.codes),
      lines3d: pick<bool>('lines3d', d.lines3d),
      contours: pick<bool>('contours', d.contours),
      contourInterval: () {
        final v = j['contourInterval'];
        return v is num && v >= 0 && v <= 100 ? v.toDouble() : d.contourInterval;
      }(),
      majorEvery: pick<int>('majorEvery', d.majorEvery, (v) => v >= 2 && v <= 10),
      showTin: pick<bool>('showTin', d.showTin),
    );
  }
}

class Layer {
  const Layer(this.name, this.color, [this.lineType = 'CONTINUOUS', this.description = '']);
  final String name;
  final int color;
  final String lineType;
  final String description;
}

/// The layers every drawing has besides the codes' own
abstract final class Layers {
  static const points = Layer('POINTS', 7, 'CONTINUOUS', 'Survey points');
  static const levels = Layer('LEVELS', 7, 'CONTINUOUS', 'Level text');
  static const numbers = Layer('POINT_NUMBERS', 8, 'CONTINUOUS', 'Point numbers');
  static const codes = Layer('POINT_CODES', 8, 'CONTINUOUS', 'Field codes');
  static const unknown = Layer('UNKNOWN_CODES', 1, 'CONTINUOUS', 'Points with a code not in the list');
  static const contourMinor = Layer('CONTOUR_MINOR', 34, 'CONTINUOUS', 'Contours');
  static const contourMajor = Layer('CONTOUR_MAJOR', 30, 'CONTINUOUS', 'Major contours');
  static const contourLabels = Layer('CONTOUR_LABELS', 30, 'CONTINUOUS', 'Contour levels');
  static const tin = Layer('TIN', 252, 'CONTINUOUS', 'Ground surface triangles');
}

class DLine {
  DLine({
    required this.layer,
    required this.feature,
    required this.number,
    required this.vertices,
    required this.closed,
    required this.pointIds,
  });
  final String layer;
  final FeatureCode feature;
  final int number;

  /// The points the line passes through, curves already broken into short straight pieces
  final List<Vertex> vertices;
  final bool closed;

  /// The survey points it was made from
  final List<String> pointIds;
}

class DSymbol {
  const DSymbol({required this.layer, required this.symbol, required this.at, required this.pointId, this.feature});
  final String layer;
  final String symbol;
  final Vertex at;
  final String pointId;

  /// The point code it shows (null for an unknown code)
  final FeatureCode? feature;
}

enum TextKind { level, number, code, contour }

class DText {
  const DText({
    required this.layer,
    required this.kind,
    required this.text,
    required this.at,
    required this.height,
    this.rotation = 0,
    this.centered = false,
  });
  final String layer;
  final TextKind kind;
  final String text;

  /// Where the text's baseline starts (left-aligned), or its middle when [centered]
  final Vertex at;
  final double height;

  /// Degrees, anticlockwise
  final double rotation;
  final bool centered;
}

enum Severity {
  /// The drawing is probably wrong here
  error,

  /// Worth a look
  warning,

  /// For information
  info,
}

/// What a problem is about, for the quick fixes the app offers
enum ProblemKind { other, unknownCode, remark }

class Problem {
  const Problem(
    this.severity,
    this.title,
    this.detail, {
    this.pointIds = const [],
    this.at,
    this.kind = ProblemKind.other,
    this.subject = '',
  });
  final Severity severity;

  final ProblemKind kind;

  /// The code or word it is about ("XX"), for [ProblemKind.unknownCode] and [ProblemKind.remark]
  final String subject;

  /// One line: "Line RE1 has only one point"
  final String title;

  /// What it means and how to fix it
  final String detail;

  /// The points it is about
  final List<String> pointIds;

  /// Where to look on the drawing
  final Vertex? at;
}

class Drawing {
  Drawing({
    required this.points,
    required this.lines,
    required this.symbols,
    required this.texts,
    required this.layers,
    required this.problems,
    required this.options,
    this.contours = const [],
    this.tin,
    this.contourInterval = 0,
  });

  final List<SurveyPoint> points;

  /// Contours from the ground surface (when switched on)
  final List<Contour> contours;

  /// The ground surface they were made from
  final Tin? tin;

  /// The interval used, in metres
  final double contourInterval;
  final List<DLine> lines;
  final List<DSymbol> symbols;
  final List<DText> texts;

  /// Every layer used, in a sensible order (features first, then points and text)
  final List<Layer> layers;
  final List<Problem> problems;
  final DraftOptions options;

  /// The box round every point and line (worked out once)
  late final Bounds? bounds = Bounds.of([
    for (final p in points) Vertex(p.e, p.n, p.z ?? 0),
    for (final l in lines) ...l.vertices,
  ]);

  Layer? layer(String name) => layers.where((l) => l.name == name).firstOrNull;
}
