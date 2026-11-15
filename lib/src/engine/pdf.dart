// The sheet as a PDF, at scale: one page of the chosen paper, the survey clipped to the drawing area,
// then the frame, grid, legend and title block. Vector throughout, so it prints sharp at any size.
// Colours as on white paper (colour 7 black, yellow darker); line types as dashes in millimetres.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

import 'aci.dart';
import 'drawing.dart';
import 'point.dart';
import 'sheet.dart';
import 'symbols.dart';

/// Inter regular and bold: passed in, so this works the same in the app and on the command line
class PdfFonts {
  const PdfFonts(this.regular, this.bold);
  final ByteData regular, bold;
}

Future<Uint8List> writePdf(Drawing d, Sheet sheet, PdfFonts fonts, {String title = ''}) async {
  const pt = 72 / 25.4; // points per mm
  final doc = PdfDocument();
  // the document's title and author, shown in a PDF reader's properties
  PdfInfo(
    doc,
    title: title.isEmpty ? 'Survey drawing' : title,
    creator: 'Auto Draft',
    producer: 'Auto Draft (www.exceltokml.com)',
  );
  final page = PdfPage(doc, pageFormat: PdfPageFormat(sheet.widthMm * pt, sheet.heightMm * pt));
  final g = page.getGraphics();
  final regular = PdfTtfFont(doc, fonts.regular), bold = PdfTtfFont(doc, fonts.bold);
  final f = sheet.f;

  // drawing (metres) → page (points)
  double x(double e) => (e - sheet.origin.e) / f * pt;
  double y(double n) => (n - sheet.origin.n) / f * pt;
  final layerColor = {
    for (final l in [...d.layers, ...SheetLayers.all]) l.name: l.color,
  };

  void dashes(String lineType) {
    final mm = switch (lineType) {
      'DASHED' => [6.0, 3.0],
      'HIDDEN' => [3.0, 1.5],
      'CENTER' => [12.0, 2.0, 2.0, 2.0],
      'DASHDOT' => [6.0, 2.0, 0.3, 2.0],
      'DOT' => [0.3, 1.5],
      _ => <double>[],
    };
    g.setLineDashPattern([for (final v in mm) v * pt]);
  }

  void polyline(List<Vertex> v, {required bool closed}) {
    if (v.isEmpty) return;
    g.moveTo(x(v.first.e), y(v.first.n));
    for (final p in v.skip(1)) {
      g.lineTo(x(p.e), y(p.n));
    }
    if (closed) g.closePath();
  }

  void symbol(String name, Vertex at, double sizeMm) {
    final def = symbols[name] ?? symbols[unknownSymbol]!;
    final s = sizeMm * pt, cx = x(at.e), cy = y(at.n);
    for (final part in def.parts) {
      switch (part) {
        case SLine(:final x1, :final y1, :final x2, :final y2):
          g.moveTo(cx + x1 * s, cy + y1 * s);
          g.lineTo(cx + x2 * s, cy + y2 * s);
          g.strokePath();
        case SCircle(x: final px, y: final py, :final r):
          g.drawEllipse(cx + px * s, cy + py * s, r * s, r * s);
          g.strokePath();
        case SPoly(:final xy, :final closed):
          g.moveTo(cx + xy[0] * s, cy + xy[1] * s);
          for (var i = 2; i + 1 < xy.length; i += 2) {
            g.lineTo(cx + xy[i] * s, cy + xy[i + 1] * s);
          }
          if (closed) g.closePath();
          g.strokePath();
      }
    }
  }

  void text(
    String s,
    Vertex at,
    double heightM, {
    SheetAlign align = SheetAlign.left,
    double rotation = 0,
    bool isBold = false,
  }) {
    final font = isBold ? bold : regular;
    // DXF text height is the capital height; a font's size is about 1.4 times it
    final size = heightM / f * pt * 1.38;
    final w = font.stringMetrics(s).advanceWidth * size;
    final dx = switch (align) {
      SheetAlign.left => 0.0,
      SheetAlign.center => -w / 2,
      SheetAlign.right => -w,
    };
    g.saveContext();
    g.setTransform(
      Matrix4.identity()
        ..translateByDouble(x(at.e), y(at.n), 0, 1)
        ..rotateZ(rotation * math.pi / 180),
    );
    g.drawString(font, size, s, dx, 0);
    g.restoreContext();
  }

  // ---- the survey, clipped to the drawing area
  g.saveContext();
  final a = sheet.area;
  g.drawRect(x(a.minE), y(a.minN), x(a.maxE) - x(a.minE), y(a.maxN) - y(a.minN));
  g.clipPath();
  g.setLineCap(PdfLineCap.round);
  g.setLineJoin(PdfLineJoin.round);
  // the surface's triangles (when shown) and the contours, under everything else
  final tin = d.tin;
  if (tin != null && d.options.showTin) {
    g.setStrokeColor(PdfColors.grey400);
    g.setLineWidth(0.07 * pt);
    for (final (a, b, c) in tin.triangles) {
      polyline([tin.points[a], tin.points[b], tin.points[c]], closed: true);
      g.strokePath();
    }
  }
  for (final c in d.contours) {
    g.setStrokeColor(_paper(c.major ? Layers.contourMajor.color : Layers.contourMinor.color));
    g.setLineWidth((c.major ? 0.3 : 0.13) * pt);
    polyline(c.vertices, closed: c.closed);
    g.strokePath();
  }
  for (final l in d.lines) {
    g.setStrokeColor(_paper(layerColor[l.layer] ?? 7));
    g.setLineWidth(0.25 * pt);
    dashes(l.feature.lineType);
    polyline(l.vertices, closed: l.closed);
    g.strokePath();
  }
  dashes('CONTINUOUS');
  g.setLineWidth(0.18 * pt);
  for (final s in d.symbols) {
    g.setStrokeColor(_paper(layerColor[s.layer] ?? 7));
    symbol(s.symbol, s.at, d.options.symbolMm);
  }
  g.setFillColor(PdfColors.grey700);
  for (final p in d.points) {
    g.drawEllipse(x(p.e), y(p.n), 0.18 * pt, 0.18 * pt);
    g.fillPath();
  }
  for (final t in d.texts) {
    g.setFillColor(_paper(layerColor[t.layer] ?? 7));
    text(t.text, t.at, t.height, rotation: t.rotation, align: t.centered ? SheetAlign.center : SheetAlign.left);
  }
  g.restoreContext();

  // ---- the sheet
  for (final item in sheet.items) {
    switch (item) {
      case SheetPolyline(:final layer, :final points, :final closed, :final color, :final lineType, :final weightMm):
        g.setStrokeColor(_paper(color ?? layerColor[layer] ?? 7));
        g.setLineWidth(weightMm * pt);
        dashes(lineType ?? 'CONTINUOUS');
        polyline(points, closed: closed);
        g.strokePath();
        dashes('CONTINUOUS');
      case SheetText(
        :final layer,
        text: final s,
        :final at,
        :final height,
        :final align,
        :final rotation,
        bold: final b,
      ):
        g.setFillColor(_paper(layerColor[layer] ?? 7));
        text(s, at, height, align: align, rotation: rotation, isBold: b);
      case SheetSolid(:final layer, :final corners):
        g.setFillColor(_paper(layerColor[layer] ?? 7));
        polyline(corners, closed: true);
        g.fillPath();
      case SheetSymbol(:final layer, symbol: final name, :final at, :final size, :final color):
        g.setStrokeColor(_paper(color ?? layerColor[layer] ?? 7));
        g.setLineWidth(0.18 * pt);
        symbol(name, at, size / f);
    }
  }
  return doc.save();
}

PdfColor _paper(int aci) {
  final (r, g, b) = aciOnPaper(aci);
  return PdfColor(r / 255, g / 255, b / 255);
}
