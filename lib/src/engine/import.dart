// Reading the survey file: a table of rows (from CSV / TXT, or Excel), which column is which,
// and the survey points. The column guess reads the header names when there are any (Point,
// Easting, Northing, Level, Code…); without a header it uses the usual P, E, N, Z, Code order,
// swapping E and N when the numbers show it (a northing in Pakistan is a 7-digit number, an
// easting 6 digits). The person can always correct the guess.
import 'dart:convert';

import 'package:excel/excel.dart';

import 'point.dart';

class Table {
  Table(this.rows, {this.delimiter = ''});

  /// The cells of each line, as written
  final List<List<String>> rows;

  /// ',', '\t', ';', ' ' or '' for Excel
  final String delimiter;

  int get columns => rows.fold(0, (m, r) => r.length > m ? r.length : m);
}

/// Reads CSV / TXT / PRN text. The delimiter is the one that splits the lines most evenly.
Table readText(String text) {
  final lines = const LineSplitter().convert(text.replaceFirst('﻿', '')).where((l) => l.trim().isNotEmpty).toList();
  final sample = lines.take(50).toList();
  String best = ',';
  var bestScore = -1.0;
  for (final d in [',', '\t', ';', ' ']) {
    final counts = [for (final l in sample) _split(l, d).length];
    if (counts.isEmpty) break;
    final common = _mode(counts);
    if (common < 3) continue;
    final share = counts.where((c) => c == common).length / counts.length;
    final score = share * 10 + common * 0.01 - (d == ' ' ? 0.5 : 0); // spaces only when nothing else fits
    if (score > bestScore) {
      bestScore = score;
      best = d;
    }
  }
  return Table([for (final l in lines) _split(l, best)], delimiter: best);
}

int _mode(List<int> xs) {
  final m = <int, int>{};
  for (final x in xs) {
    m[x] = (m[x] ?? 0) + 1;
  }
  return m.entries.reduce((a, b) => b.value > a.value || (b.value == a.value && b.key > a.key) ? b : a).key;
}

List<String> _split(String line, String d) {
  if (d == ' ') return line.trim().split(RegExp(r'\s+'));
  // quoted cells may hold the delimiter: "RE1, ST"
  final out = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == d && !quoted) {
      out.add(cell.toString().trim());
      cell.clear();
    } else {
      cell.write(ch);
    }
  }
  out.add(cell.toString().trim());
  return out;
}

/// Reads the first sheet of an Excel workbook (.xlsx) that has data
Table readExcel(List<int> bytes) {
  final book = Excel.decodeBytes(bytes);
  for (final name in book.tables.keys) {
    final sheet = book.tables[name]!;
    final rows = <List<String>>[];
    for (final r in sheet.rows) {
      final cells = [for (final c in r) _cell(c?.value)];
      while (cells.isNotEmpty && cells.last.isEmpty) {
        cells.removeLast();
      }
      if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
    }
    if (rows.isNotEmpty) return Table(rows);
  }
  return Table([]);
}

String _cell(CellValue? v) => switch (v) {
  null => '',
  IntCellValue(:final value) => '$value',
  DoubleCellValue(:final value) => _num(value),
  TextCellValue() => v.value.toString().trim(),
  _ => v.toString().trim(),
};

String _num(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  return v.toString();
}

/// Which column holds what; -1 when there is none
class ColumnMap {
  const ColumnMap({this.id = 0, this.e = 1, this.n = 2, this.z = 3, this.code = 4, this.headerRows = 0});
  final int id, e, n, z, code;

  /// Lines at the top that are titles or column names, not points
  final int headerRows;

  ColumnMap copyWith({int? id, int? e, int? n, int? z, int? code, int? headerRows}) => ColumnMap(
    id: id ?? this.id,
    e: e ?? this.e,
    n: n ?? this.n,
    z: z ?? this.z,
    code: code ?? this.code,
    headerRows: headerRows ?? this.headerRows,
  );

  @override
  bool operator ==(Object other) =>
      other is ColumnMap &&
      other.id == id &&
      other.e == e &&
      other.n == n &&
      other.z == z &&
      other.code == code &&
      other.headerRows == headerRows;

  @override
  int get hashCode => Object.hash(id, e, n, z, code, headerRows);

  @override
  String toString() => 'ColumnMap(id $id, e $e, n $n, z $z, code $code, header $headerRows)';
}

double? _number(String s) => double.tryParse(s.trim().replaceAll(RegExp(r'\s'), ''));

bool _numeric(String s) => _number(s) != null;

const _names = {
  'id': [
    'P',
    'PT',
    'PNT',
    'POINT',
    'POINTNO',
    'POINTNUMBER',
    'NO',
    'NUMBER',
    'ID',
    'NAME',
    'PTNO',
    'STN',
    'STATION',
    'SNO',
  ],
  'e': ['E', 'EAST', 'EASTING', 'EASTINGS', 'X', 'EASTINGM'],
  'n': ['N', 'NORTH', 'NORTHING', 'NORTHINGS', 'Y', 'NORTHINGM'],
  'z': ['Z', 'RL', 'LEVEL', 'LEVELS', 'ELEV', 'ELEVATION', 'H', 'HEIGHT', 'HT', 'LEVELM', 'ELEVATIONM'],
  'code': ['CODE', 'CODES', 'D', 'DESC', 'DESCRIPTION', 'FEATURE', 'REMARK', 'REMARKS', 'FEATURECODE', 'PCODE'],
};

String _key(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');

/// The best guess for a table
ColumnMap guessColumns(Table t) {
  if (t.rows.isEmpty) return const ColumnMap();
  // a header: the first lines that have no numbers where the points have them
  var header = 0;
  while (header < t.rows.length && header < 5 && t.rows[header].where(_numeric).length < 3) {
    header++;
  }
  if (header == t.rows.length) header = 0;
  final cols = t.columns;
  if (header > 0) {
    final names = t.rows[header - 1].map(_key).toList();
    int find(String what) => names.indexWhere((n) => _names[what]!.contains(n));
    final m = ColumnMap(
      id: find('id'),
      e: find('e'),
      n: find('n'),
      z: find('z'),
      code: find('code'),
      headerRows: header,
    );
    if (m.e >= 0 && m.n >= 0) return m;
  }
  // by the values: the numeric columns, then text for the code
  final data = t.rows.skip(header).take(200).toList();
  bool mostlyNumeric(int c) {
    final vals = [
      for (final r in data)
        if (c < r.length && r[c].isNotEmpty) r[c],
    ];
    return vals.isNotEmpty && vals.where(_numeric).length >= vals.length * 0.9;
  }

  final numeric = [
    for (var c = 0; c < cols; c++)
      if (mostlyNumeric(c)) c,
  ];
  final text = [
    for (var c = 0; c < cols; c++)
      if (!numeric.contains(c)) c,
  ];
  // P E N Z: the first column is the point number when there are four or more numeric ones, or
  // when it is text (STN1)
  var id = -1;
  var coords = numeric;
  if (numeric.length >= 4 && numeric.first == 0) {
    id = 0;
    coords = numeric.sublist(1);
  } else if (text.isNotEmpty && text.first == 0) {
    id = 0;
  }
  if (coords.length < 2) return ColumnMap(headerRows: header);
  var e = coords[0], n = coords[1];
  // northing first? (N E Z order): a 7-digit first and 6-digit second number
  double avg(int c) {
    final v = [
      for (final r in data)
        if (c < r.length) ?_number(r[c]),
    ];
    return v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
  }

  if (avg(e).abs() >= 1000000 && avg(n).abs() < 1000000) {
    final s = e;
    e = n;
    n = s;
  }
  final z = coords.length >= 3 ? coords[2] : -1;
  final code =
      [...text.where((c) => c != id), ...numeric.where((c) => c != id && !coords.take(3).contains(c))].firstOrNull ??
      -1;
  return ColumnMap(id: id, e: e, n: n, z: z, code: code, headerRows: header);
}

class ImportResult {
  const ImportResult(this.points, this.skipped);
  final List<SurveyPoint> points;

  /// Lines that weren't points: (line number, why)
  final List<(int, String)> skipped;
}

ImportResult readPoints(Table t, ColumnMap m) {
  final points = <SurveyPoint>[];
  final skipped = <(int, String)>[];
  String at(List<String> r, int c) => c >= 0 && c < r.length ? r[c] : '';
  for (var i = m.headerRows; i < t.rows.length; i++) {
    final r = t.rows[i];
    final e = _number(at(r, m.e)), n = _number(at(r, m.n));
    if (e == null || n == null) {
      skipped.add((i + 1, 'no easting or northing'));
      continue;
    }
    final zs = at(r, m.z).trim();
    final z = zs.isEmpty ? null : _number(zs);
    if (zs.isNotEmpty && z == null) {
      skipped.add((i + 1, 'the level "$zs" isn\'t a number'));
      continue;
    }
    final id = at(r, m.id).trim();
    points.add(
      SurveyPoint(
        id: id.isEmpty ? '${points.length + 1}' : id,
        e: e,
        n: n,
        z: z,
        code: at(r, m.code).trim(),
        row: i + 1,
      ),
    );
  }
  return ImportResult(points, skipped);
}
