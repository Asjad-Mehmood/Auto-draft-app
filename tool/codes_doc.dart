// Writes docs/CODES.md from the code list in the app, so the guide always matches it.
//   dart run tool/codes_doc.dart > docs/CODES.md     (CI checks it is up to date)
import 'package:auto_draft/src/engine/codes.dart';
import 'package:auto_draft/src/engine/symbols.dart';

void main() {
  final all = CodeLibrary.defaults().all;
  final b = StringBuffer()
    ..writeln('# Auto Draft: field codes')
    ..writeln()
    ..writeln('<!-- Made by tool/codes_doc.dart from lib/src/engine/codes.dart. Edit those, not this file. -->')
    ..writeln()
    ..writeln('Type the code in the total station\'s code field. Upper or lower case; words are separated by spaces')
    ..writeln('(commas, semicolons and slashes work too).')
    ..writeln()
    ..writeln('## Lines and their number')
    ..writeln()
    ..writeln('Points with the same **line code and number** are joined into one line, in the order they were')
    ..writeln('surveyed: `RE1` is road edge 1, `RE2` road edge 2. A code without a number (`RE`) is line 0.')
    ..writeln('Lines can be surveyed mixed together: `RE1`, `RE2`, `RE1`, `RE2`… still makes two lines.')
    ..writeln()
    ..writeln('## Control words')
    ..writeln()
    ..writeln('Written after the code they steer.')
    ..writeln()
    ..writeln('| Word | Example | What it does |')
    ..writeln('|---|---|---|')
    ..writeln('| `ST` (or `START`) | `RE1 ST` | Starts a new line here; the line before it ends |')
    ..writeln('| `END` | `RE1 END` | This is the line\'s last point |')
    ..writeln('| `CLS` (or `CLOSE`) | `BLD1 CLS` | Closes the shape back to its first point |')
    ..writeln(
      '| `RECT` | `BLD2 RECT` | On the 3rd corner: the 4th corner is added (a rectangle) and the shape closed |',
    )
    ..writeln('| `ARC` | `WL1 ARC` | A curve starts here |')
    ..writeln('| `EARC` (or `ENDARC`) | `WL1 EARC` | The curve ends here; `EARC ARC` starts the next curve at once |')
    ..writeln()
    ..writeln('A point can be on two lines: `WL1 GT1` is on wall 1 and gate 1. A word that is neither a code nor a')
    ..writeln('control word is kept as a remark (`TR NEEM`). Three points make a curve as a circular arc; more points')
    ..writeln('a smooth curve through every one.')
    ..writeln();
  for (final kind in CodeKind.values) {
    b
      ..writeln(kind == CodeKind.line ? '## Line codes' : '## Point codes')
      ..writeln()
      ..writeln(
        kind == CodeKind.line
            ? '| Code | Feature | Layer | Colour | Line type |'
            : '| Code | Feature | Layer | Colour | Symbol |',
      )
      ..writeln('|---|---|---|---|---|');
    for (final c in all.where((c) => c.kind == kind)) {
      final last = kind == CodeKind.line ? c.lineType.toLowerCase() : (symbols[c.symbol]?.label ?? c.symbol);
      b.writeln('| `${c.code}` | ${c.name} | `${c.layer}` | ${c.color} | $last |');
    }
    b.writeln();
  }
  b
    ..writeln('## Other layers')
    ..writeln()
    ..writeln('`POINTS` (a point at every survey point, at its level), `LEVELS` (level text), `POINT_NUMBERS` and')
    ..writeln(
      '`POINT_CODES` (when switched on in the settings) and `UNKNOWN_CODES` (points whose code isn\'t in the list).',
    )
    ..writeln()
    ..writeln('Colours are AutoCAD colour numbers (1 red, 2 yellow, 3 green, 4 cyan, 5 blue, 6 magenta, 7 white/black,')
    ..writeln('8 grey). Your own list: Codes tab → Save this list, edit, Load a code list.');
  // ignore: avoid_print
  print(b.toString().trimRight());
}
