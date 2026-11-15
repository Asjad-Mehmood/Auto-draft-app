// Auto Draft on the command line: a survey file in, a DXF out, and the problems listed.
//
//   dart run tool/autodraft.dart survey.csv drawing.dxf [--scale 500] [--3d] [--numbers] [--codes]
//                                                        [--code-list codes.json]
//
// Used by the checks (tool/check_dxf.py opens what it writes) and handy for trying a file.
import 'dart:io';

import 'package:auto_draft/src/engine/builder.dart';
import 'package:auto_draft/src/engine/codes.dart';
import 'package:auto_draft/src/engine/drawing.dart';
import 'package:auto_draft/src/engine/dxf.dart';
import 'package:auto_draft/src/engine/import.dart';

void main(List<String> args) {
  final files = <String>[];
  var options = const DraftOptions();
  var library = CodeLibrary.defaults();
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--scale':
        options = options.copyWith(scale: int.parse(args[++i]));
      case '--3d':
        options = options.copyWith(lines3d: true);
      case '--numbers':
        options = options.copyWith(pointNumbers: true);
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
      'usage: dart run tool/autodraft.dart survey.csv|.txt|.xlsx drawing.dxf [--scale 500] [--3d] [--numbers] [--codes]',
    );
    exit(2);
  }
  final input = File(files[0]);
  final table = input.path.toLowerCase().endsWith('.xlsx')
      ? readExcel(input.readAsBytesSync())
      : readText(input.readAsStringSync());
  final columns = guessColumns(table);
  final read = readPoints(table, columns);
  final drawing = buildDrawing(read.points, library, options);
  File(files[1]).writeAsStringSync(writeDxf(drawing), flush: true);
  stdout.writeln(
    '${read.points.length} points, ${drawing.lines.length} lines, ${drawing.symbols.length} symbols, '
    '${drawing.texts.length} texts, ${drawing.layers.length} layers -> ${files[1]}',
  );
  stdout.writeln('columns: $columns');
  for (final (line, why) in read.skipped) {
    stdout.writeln('skipped line $line: $why');
  }
  for (final p in drawing.problems) {
    stdout.writeln('[${p.severity.name}] ${p.title}');
  }
}
