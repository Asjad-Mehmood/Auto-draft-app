// Auto Draft on the command line: a survey file in, a DXF out, and the problems listed.
//
//   dart run tool/autodraft.dart survey.csv drawing.dxf [--scale 500] [--3d] [--numbers] [--codes]
//                                                        [--code-list codes.json]
//
// Used by the checks (tool/check_dxf.py opens what it writes) and handy for trying a file.
import 'dart:io';
import 'dart:typed_data';

import 'package:auto_draft/src/engine/builder.dart';
import 'package:auto_draft/src/engine/codes.dart';
import 'package:auto_draft/src/engine/drawing.dart';
import 'package:auto_draft/src/engine/dxf.dart';
import 'package:auto_draft/src/engine/import.dart';
import 'package:auto_draft/src/engine/instruments.dart';
import 'package:auto_draft/src/engine/kml.dart';
import 'package:auto_draft/src/engine/pdf.dart';
import 'package:auto_draft/src/engine/sheet.dart';

Future<void> main(List<String> args) async {
  final files = <String>[];
  var options = const DraftOptions();
  var library = CodeLibrary.defaults();
  SheetInfo? sheet;
  String? pdfPath, kmlPath;
  var zone = 43;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--scale':
        options = options.copyWith(scale: int.parse(args[++i]));
      case '--3d':
        options = options.copyWith(lines3d: true);
      case '--numbers':
        options = options.copyWith(pointNumbers: true);
      case '--sheet':
        // --sheet auto | A4 … A0
        final p = args[++i].toLowerCase();
        sheet = (sheet ?? const SheetInfo()).copyWith(paper: () => Paper.values.where((x) => x.name == p).firstOrNull);
      case '--contours':
        // --contours auto | 0.5
        final v = args[++i];
        options = options.copyWith(contours: true, contourInterval: v == 'auto' ? 0 : double.parse(v));
      case '--tin':
        options = options.copyWith(showTin: true);
      case '--kml':
        kmlPath = args[++i];
      case '--zone':
        zone = int.parse(args[++i]);
      case '--pdf':
        pdfPath = args[++i];
        sheet ??= const SheetInfo();
      case '--title':
        sheet = (sheet ?? const SheetInfo()).copyWith(title: args[++i]);
      case '--firm':
        sheet = (sheet ?? const SheetInfo()).copyWith(firm: args[++i]);
      case '--codes':
        options = options.copyWith(codes: true);
      case '--code-list':
        final l = CodeLibrary.fromJsonString(File(args[++i]).readAsStringSync());
        if (l == null) {
          stderr.writeln('${args[i]} is not an Auto Draft code list');
          exit(2);
        }
        library = l;
      default:
        files.add(args[i]);
    }
  }
  if (files.length != 2) {
    stderr.writeln(
      'usage: dart run tool/autodraft.dart survey.csv|.txt|.xlsx|.gsi|.sdr|.raw drawing.dxf [--scale 500] [--3d] [--numbers] [--codes] [--sheet auto|a4..a0] [--pdf out.pdf] [--kml out.kml --zone 43] [--contours auto|0.5] [--tin] [--title T] [--firm F]',
    );
    exit(2);
  }
  final input = File(files[0]);
  final inst = input.path.toLowerCase().endsWith('.xlsx') ? null : readInstrument(input.path, input.readAsStringSync());
  final table =
      inst?.table ??
      (input.path.toLowerCase().endsWith('.xlsx')
          ? readExcel(input.readAsBytesSync())
          : readText(input.readAsStringSync()));
  final columns = inst == null ? guessColumns(table) : const ColumnMap();
  if (inst != null) stdout.writeln('${inst.format}: ${inst.notes.join('; ')}');
  final read = readPoints(table, columns);
  final drawing = buildDrawing(read.points, library, options);
  final sh = sheet == null ? null : buildSheet(drawing, sheet);
  File(files[1]).writeAsStringSync(writeDxf(drawing, sheet: sh), flush: true);
  if (kmlPath != null) {
    File(kmlPath).writeAsStringSync(writeKml(drawing, zone: zone, title: sheet?.title ?? ''), flush: true);
    stdout.writeln('kml: $kmlPath (UTM zone ${zone}N)');
  }
  if (sh != null && pdfPath != null) {
    ByteData font(String f) => ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync());
    final bytes = await writePdf(
      drawing,
      sh,
      PdfFonts(font('Inter_400Regular.ttf'), font('Inter_700Bold.ttf')),
      title: sheet!.title,
    );
    File(pdfPath).writeAsBytesSync(bytes, flush: true);
    stdout.writeln('pdf: $pdfPath (${(bytes.length / 1024).round()} KB)');
  }
  if (sh != null) {
    stdout.writeln(
      'sheet: ${sh.label}, grid every ${sh.gridInterval} m${sh.fits ? '' : ' - DOES NOT FIT: ${sh.advice}'}',
    );
  }
  stdout.writeln(
    '${read.points.length} points, ${drawing.lines.length} lines, ${drawing.symbols.length} symbols, '
    '${drawing.texts.length} texts, ${drawing.layers.length} layers -> ${files[1]}',
  );
  stdout.writeln('columns: $columns');
  if (drawing.tin != null) {
    stdout.writeln(
      'surface: ${drawing.tin!.triangles.length} triangles; ${drawing.contours.length} contours every ${drawing.contourInterval} m',
    );
  }
  for (final (line, why) in read.skipped) {
    stdout.writeln('skipped line $line: $why');
  }
  for (final p in drawing.problems) {
    stdout.writeln('[${p.severity.name}] ${p.title}');
  }
}
