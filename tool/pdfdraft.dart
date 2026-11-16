// PDF to drawing on the command line: a PDF printed from CAD in, a DXF with proper layers, line
// types, hatches, dimensions and text out.
//
//   dart run tool/pdfdraft.dart plan.pdf plan.dxf [--page 1] [--scale 200 | --scale auto] [--no-layers]
//
// Used by the checks (tool/check_dxf.py opens what it writes) and handy for trying a file.
import 'dart:io';

import 'package:auto_draft/src/engine/pdf_in/pdf_drafting.dart';

void main(List<String> args) {
  final files = <String>[];
  var page = 1;
  int? scale;
  var auto = false;
  var layers = true;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--page':
        page = int.parse(args[++i]);
      case '--scale':
        final s = args[++i];
        if (s == 'auto') {
          auto = true;
        } else {
          scale = int.parse(s);
        }
      case '--no-layers':
        layers = false;
      default:
        files.add(args[i]);
    }
  }
  if (files.length != 2) {
    stderr.writeln('usage: dart run tool/pdfdraft.dart plan.pdf plan.dxf [--page 1] [--scale 200|auto] [--no-layers]');
    exit(64);
  }
  try {
    final pdf = PdfDrawingFile.open(File(files[0]).readAsBytesSync());
    final d = pdf.draft(
      page - 1,
      options: PdfDraftOptions(scale: scale, useLayers: layers),
      autoScale: auto,
    );
    File(files[1]).writeAsStringSync(pdfDrawingToDxf(d.drawing));
    final c = d.drawing;
    stdout.writeln(
      '${files[1]}: page $page of ${pdf.pageCount}, ${c.units == 'm' ? 'metres at 1:${c.scale}' : 'millimetres on paper'}',
    );
    stdout.writeln('  ${c.counts.entries.map((e) => '${e.value} ${e.key}').join(', ')}');
    stdout.writeln('  layers: ${c.layers.values.map((l) => '${l.name} (${l.aci}, ${l.lineType})').join(', ')}');
    if (d.suggestedScale != null) stdout.writeln('  the dimensions say 1:${d.suggestedScale}');
    for (final n in c.notes) {
      stdout.writeln('  note: $n');
    }
  } on PdfReadError catch (e) {
    stderr.writeln(e.message);
    exit(1);
  }
}
