// Files straight from the total station, read into the same table as a CSV (Point, E, N, Z, Code):
//
//   Leica GSI (GSI-8 and GSI-16): coordinates (words 81 82 83), or worked out from the measurements
//     (21 Hz, 22 V, 31 slope or 32 horizontal distance) from the station (84 85 86, 88 instrument
//     height, 87 target height); codes from words 71-79 (code, then ST, CLS…) or a code block
//     (41-49) before the point.
//   Sokkia SDR (SDR33 / SDR2x): coordinate records (08), 16- or 4-character point numbers.
//   Nikon RAW: coordinate records (CP, MP, UP, CC), and side shots (SS) worked out from their station
//     (ST) and back-sight azimuth.
//
// Written from the formats' specifications: the readers tell what they read and what they skipped.
import 'dart:math' as math;

import 'import.dart';

class InstrumentRead {
  InstrumentRead(this.format, this.table, this.notes);

  /// "Leica GSI-16"
  final String format;

  /// Point, Easting, Northing, Level, Code; no header line
  final Table table;

  /// What was read and skipped, for the person
  final List<String> notes;
}

/// The instrument formats by file extension; null for other files
InstrumentRead? readInstrument(String name, String text) {
  final ext = name.toLowerCase().split('.').last;
  final lines = text.replaceFirst('﻿', '').split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  if (ext == 'gsi' || (lines.isNotEmpty && _looksGsi(lines.first))) return _gsi(lines);
  if (ext == 'sdr') return _sdr(lines);
  if (ext == 'raw') return _nikon(lines);
  return null;
}

bool _looksGsi(String l) => RegExp(r'^\*?11\d{4}[+-][0-9A-Za-z]{8,16} ').hasMatch(l.trimLeft());

List<String> _row(String id, double e, double n, double? z, String code) => [
  id,
  e.toStringAsFixed(4),
  n.toStringAsFixed(4),
  z == null ? '' : z.toStringAsFixed(4),
  code,
];

// ------------------------------------------------------------------ Leica GSI

/// A GSI word: index, the 4 information characters, and the signed data
class _Word {
  _Word(this.wi, this.info, this.data);
  final int wi;
  final String info;
  final String data;

  /// The units digit (the 6th character of the word)
  String get unit => info.length >= 4 ? info[3] : '0';

  String get text {
    final t = data.substring(1).replaceFirst(RegExp(r'^0+'), '');
    return t;
  }

  double? get length {
    final v = int.tryParse(data.substring(1));
    if (v == null) return null;
    final sign = data.startsWith('-') ? -1 : 1;
    final scale = switch (unit) {
      '6' || '7' => 1e-4,
      '8' => 1e-5,
      _ => 1e-3, // 0 metres (mm), 1 feet (1/1000 ft)
    };
    return sign * v * scale;
  }

  /// An angle in radians
  double? get angle {
    final digits = data.substring(1);
    final v = int.tryParse(digits);
    if (v == null) return null;
    double dms(int x, int fracDigits) {
      final f = math.pow(10, fracDigits).toInt();
      final secs = (x % (100 * f)) / f;
      final mins = (x ~/ (100 * f)) % 100;
      final degs = x ~/ (10000 * f);
      return degs + mins / 60 + secs / 3600;
    }

    final degrees = switch (unit) {
      '2' => v / 1e5 * 0.9, // 400 gon
      '3' => v / 1e5,
      '4' => dms(v, 1), // DDD MM SS.s
      '5' => v / 1e4 * 360 / 6400, // mil
      '6' => v / 1e6 * 0.9,
      '7' => v / 1e6,
      '8' => dms(v, 2),
      _ => v / 1e5 * 0.9,
    };
    return degrees * math.pi / 180;
  }
}

List<_Word> _words(String line) {
  final out = <_Word>[];
  for (final w in line.replaceFirst('*', '').trim().split(RegExp(r'\s+'))) {
    final m = RegExp(r'^(\d{2})(.{4})([+-].+)$').firstMatch(w);
    if (m == null) continue;
    out.add(_Word(int.parse(m.group(1)!), m.group(2)!, m.group(3)!));
  }
  return out;
}

InstrumentRead _gsi(List<String> lines) {
  final rows = <List<String>>[];
  final notes = <String>[];
  final sixteen = lines.any((l) => l.startsWith('*'));
  double? e0, n0, h0;
  var hi = 0.0, hr = 0.0;
  var pendingCode = '';
  var fromCoords = 0, fromObs = 0, noStation = 0;
  for (final line in lines) {
    final ws = {for (final w in _words(line)) w.wi: w};
    if (ws.isEmpty) continue;
    // a code block before the point: the code (41) and its information words (42-49)
    if (ws[41] != null && ws[11] == null) {
      pendingCode = [for (var wi = 41; wi <= 49; wi++) ws[wi]?.text ?? ''].where((t) => t.isNotEmpty).join(' ');
      continue;
    }
    // the station: its coordinates and heights
    if (ws[84] != null || ws[85] != null) {
      e0 = ws[84]?.length ?? e0;
      n0 = ws[85]?.length ?? n0;
      h0 = ws[86]?.length ?? h0;
    }
    if (ws[88] != null) hi = ws[88]!.length ?? hi;
    if (ws[87] != null) hr = ws[87]!.length ?? hr;
    final id = ws[11]?.text ?? '';
    // the code (71) and further words (72-79: ST, CLS…), as GSI words hold no spaces
    final words = [for (var wi = 71; wi <= 79; wi++) ws[wi]?.text ?? ''].where((t) => t.isNotEmpty).join(' ');
    final code = words.isNotEmpty ? words : pendingCode;
    final e = ws[81]?.length, n = ws[82]?.length;
    if (e != null && n != null) {
      rows.add(_row(id, e, n, ws[83]?.length, code));
      fromCoords++;
      pendingCode = '';
      continue;
    }
    final hz = ws[21]?.angle, v = ws[22]?.angle;
    final sd = ws[31]?.length, hd = ws[32]?.length;
    if (hz != null && (sd != null || hd != null)) {
      if (e0 == null || n0 == null) {
        noStation++;
        continue;
      }
      final horiz = hd ?? sd! * math.sin(v ?? math.pi / 2);
      final dz = ws[33]?.length ?? (sd != null && v != null ? sd * math.cos(v) : 0.0);
      final z = h0 == null ? null : h0 + hi + dz - hr;
      rows.add(_row(id, e0 + horiz * math.sin(hz), n0 + horiz * math.cos(hz), z, code));
      fromObs++;
      pendingCode = '';
    }
  }
  if (fromCoords > 0) notes.add('$fromCoords point${fromCoords == 1 ? '' : 's'} with coordinates');
  if (fromObs > 0) notes.add('$fromObs worked out from the measurements and the station');
  if (noStation > 0) {
    notes.add(
      '$noStation measurement${noStation == 1 ? '' : 's'} skipped: no station coordinates before them (words 84, 85)',
    );
  }
  return InstrumentRead(sixteen ? 'Leica GSI-16' : 'Leica GSI-8', Table(rows, delimiter: 'gsi'), notes);
}

// ------------------------------------------------------------------ Sokkia SDR

InstrumentRead _sdr(List<String> lines) {
  final rows = <List<String>>[];
  final coords = lines.where((l) => l.startsWith('08')).toList();
  final long = coords.any((l) => l.length >= 68);
  String cut(String l, int a, int b) => l.length <= a ? '' : l.substring(a, math.min(b, l.length)).trim();
  var skipped = 0;
  for (final l in coords) {
    final (id, n, e, z, code) = long
        ? (cut(l, 4, 20), cut(l, 20, 36), cut(l, 36, 52), cut(l, 52, 68), cut(l, 68, 84))
        : (cut(l, 4, 8), cut(l, 8, 18), cut(l, 18, 28), cut(l, 28, 38), cut(l, 38, 54));
    final ne = double.tryParse(n), ee = double.tryParse(e);
    if (ne == null || ee == null) {
      skipped++;
      continue;
    }
    rows.add(_row(id, ee, ne, double.tryParse(z), code));
  }
  final obs = lines.where((l) => l.startsWith('09')).length;
  return InstrumentRead('Sokkia SDR', Table(rows, delimiter: 'sdr'), [
    '${rows.length} coordinate record${rows.length == 1 ? '' : 's'} (08)',
    if (skipped > 0) '$skipped coordinate record${skipped == 1 ? '' : 's'} without numbers skipped',
    if (obs > 0)
      '$obs measurement record${obs == 1 ? '' : 's'} (09) not used: reduce them to coordinates on the instrument or in Sokkia Link',
  ]);
}

// ------------------------------------------------------------------ Nikon RAW

InstrumentRead _nikon(List<String> lines) {
  final rows = <List<String>>[];
  final known = <String, (double, double, double?)>{};
  var decimalDegrees = false;
  // the current station: coordinates, instrument height, and the azimuth that HA 0 points to
  (double, double, double?)? station;
  var hi = 0.0, orientation = 0.0;
  var fromCoords = 0, fromObs = 0, noStation = 0;
  double angle(String s) {
    final v = double.tryParse(s) ?? 0;
    if (decimalDegrees) return v * math.pi / 180;
    // DDD.MMSS
    final d = v.truncate();
    final mm = ((v - d) * 100 + 1e-9).truncate();
    final ss = ((v - d) * 100 - mm) * 100;
    return (d + mm / 60 + ss / 3600) * math.pi / 180;
  }

  for (final line in lines) {
    final f = line.split(',').map((s) => s.trim()).toList();
    String at(int i) => i < f.length ? f[i] : '';
    switch (at(0)) {
      case 'CO':
        final c = line.toUpperCase();
        if (c.contains('ANGLE') && c.contains('DEG') && !c.contains('DMS') && !c.contains('DDDMMSS')) {
          decimalDegrees = true;
        }
      case 'CP' || 'MP' || 'UP' || 'CC' || 'RE' when double.tryParse(at(3)) != null && double.tryParse(at(4)) != null:
        final n = double.parse(at(3)), e = double.parse(at(4)), z = double.tryParse(at(5));
        known[at(1)] = (e, n, z);
        rows.add(_row(at(1), e, n, z, at(6)));
        fromCoords++;
      case 'ST':
        // ST,station,,back-sight,,HI,back azimuth,back HA
        station = known[at(1)];
        hi = double.tryParse(at(5)) ?? 0;
        orientation = angle(at(6)) - angle(at(7));
      case 'SS' || 'F1' || 'F2':
        // SS,point,target height,slope distance,HA,VA (zenith),time,code
        final s = station;
        final sd = double.tryParse(at(3));
        if (s == null || sd == null) {
          noStation++;
          continue;
        }
        final ht = double.tryParse(at(2)) ?? 0;
        final az = orientation + angle(at(4)), va = angle(at(5));
        final h = sd * math.sin(va);
        final e = s.$1 + h * math.sin(az), n = s.$2 + h * math.cos(az);
        final z = s.$3 == null ? null : s.$3! + hi + sd * math.cos(va) - ht;
        known[at(1)] = (e, n, z);
        rows.add(_row(at(1), e, n, z, at(7)));
        fromObs++;
    }
  }
  return InstrumentRead('Nikon RAW', Table(rows, delimiter: 'raw'), [
    if (fromCoords > 0) '$fromCoords point${fromCoords == 1 ? '' : 's'} with coordinates',
    if (fromObs > 0) '$fromObs side shot${fromObs == 1 ? '' : 's'} worked out from the station',
    if (noStation > 0)
      '$noStation side shot${noStation == 1 ? '' : 's'} skipped: the station has no coordinates in the file',
  ]);
}
