// What the window shows: the open survey, how its columns are read, the drawing settings, the
// code list and the drawing made from them. A change to any of them redraws at once.
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../engine/builder.dart';
import '../engine/codes.dart';
import '../engine/drawing.dart';
import '../engine/dxf.dart';
import '../engine/import.dart';
import '../engine/instruments.dart';
import '../engine/kml.dart';
import '../engine/pdf.dart';
import '../engine/point.dart';
import '../engine/sheet.dart';
import 'store.dart';

/// A file that was read, waiting for its columns to be confirmed
class OpenedFile {
  const OpenedFile(this.name, this.table, this.guess, {this.format = '', this.notes = const []});
  final String name;
  final Table table;
  final ColumnMap guess;

  /// A total station file: "Leica GSI-16"; empty for CSV, TXT and Excel
  final String format;

  /// What the instrument reader read and skipped
  final List<String> notes;
}

/// Where the drawing should look: a problem or a point picked in the side panel
class FocusRequest {
  const FocusRequest(this.at, this.pointIds);
  final Vertex at;
  final List<String> pointIds;
}

/// One step that can be undone: the points and the code list as they were before it
class _Step {
  const _Step(this.label, this.points, this.library);
  final String label;
  final List<SurveyPoint> points;
  final CodeLibrary library;
}

class AppState extends ChangeNotifier {
  AppState(this.store) {
    options = DraftOptions.fromJson(store.readJson('options'));
    sheetInfo = SheetInfo.fromJson(store.readJson('sheet'));
    final saved = store.read('codes');
    library = (saved == null ? null : CodeLibrary.fromJsonString(saved)) ?? CodeLibrary.defaults();
  }

  final Store store;
  late DraftOptions options;
  late CodeLibrary library;

  /// The title block and paper; the firm, people, notes and paper are remembered between surveys
  late SheetInfo sheetInfo;

  /// The printed sheet around the drawing (made with every redraw)
  Sheet? sheet;

  /// The sheet is drawn on screen and in the DXF
  bool get showSheet => sheet != null && sheetInfo.inDxf;

  String? fileName;
  Table? table;
  ColumnMap columns = const ColumnMap();
  List<SurveyPoint> points = const [];
  List<(int, String)> skipped = const [];
  Drawing? drawing;

  /// Layers switched off in the preview
  final hiddenLayers = <String>{};

  /// The problem picked in the list, by its place
  int? selectedProblem;
  final focus = ValueNotifier<FocusRequest?>(null);

  bool get hasDrawing => drawing != null;

  /// Goes up each time a file is opened, so the drawing view fits the new survey to the window
  int fileGeneration = 0;

  /// The point picked on the drawing or in the list, by its place in [points]
  int? picked;

  /// Each point's code as the file had it, to count and show the corrections
  List<String> _fileCodes = const [];

  final _undo = <_Step>[];
  final _redo = <_Step>[];
  static const _historySize = 100;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// What Undo / Redo would do: "Undo: code of point 8"
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;

  /// How many points have a code different from the file's
  int get changedCodes {
    var n = 0;
    for (var i = 0; i < points.length && i < _fileCodes.length; i++) {
      if (points[i].code != _fileCodes[i]) n++;
    }
    return n;
  }

  /// The code the file had for a point, when it was changed here; null otherwise
  String? fileCodeOf(int i) => i < _fileCodes.length && points[i].code != _fileCodes[i] ? _fileCodes[i] : null;

  /// Reads a file's bytes into a table and guesses its columns; null when nothing could be read.
  /// Throws a [FormatException] with a message for the person when the file isn't usable.
  static OpenedFile read(String name, Uint8List bytes) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.xls')) {
      throw const FormatException(
        'Old Excel files (.xls) can\'t be read. In Excel, use File > Save As > Excel Workbook (.xlsx), then open that.',
      );
    }
    final Table t;
    if (lower.endsWith('.xlsx')) {
      try {
        t = readExcel(bytes);
      } catch (_) {
        throw const FormatException(
          'This Excel file couldn\'t be read. Check it opens in Excel and is saved as .xlsx.',
        );
      }
    } else {
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        text = latin1.decode(bytes); // older Windows programs write ANSI
      }
      final inst = readInstrument(name, text);
      if (inst != null) {
        if (inst.table.rows.isEmpty) {
          throw FormatException('No points could be read from this ${inst.format} file. ${inst.notes.join('. ')}');
        }
        return OpenedFile(name, inst.table, const ColumnMap(), format: inst.format, notes: inst.notes);
      }
      t = readText(text);
    }
    if (t.rows.isEmpty) throw const FormatException('The file is empty.');
    return OpenedFile(name, t, guessColumns(t));
  }

  /// Uses a file with its confirmed columns
  void open(OpenedFile f, ColumnMap m) {
    fileName = f.name;
    table = f.table;
    columns = m;
    final r = readPoints(f.table, m);
    points = r.points;
    // a new survey: its own title, place, client, number and date
    sheetInfo = sheetInfo.copyWith(title: '', location: '', client: '', drawingNo: '', date: '');
    _fileCodes = [for (final p in r.points) p.code];
    skipped = r.skipped;
    hiddenLayers.clear();
    picked = null;
    _undo.clear();
    _redo.clear();
    fileGeneration++;
    focus.value = null;
    _rebuild();
  }

  void close() {
    fileName = null;
    table = null;
    points = const [];
    skipped = const [];
    drawing = null;
    sheet = null;
    selectedProblem = null;
    picked = null;
    _fileCodes = const [];
    _undo.clear();
    _redo.clear();
    focus.value = null;
    notifyListeners();
  }

  void setSheetInfo(SheetInfo i) {
    // the sheet appearing, going or changing size: fit the view again
    if (i.inDxf != sheetInfo.inDxf || i.paper != sheetInfo.paper || i.portrait != sheetInfo.portrait) fileGeneration++;
    sheetInfo = i;
    store.writeJson('sheet', i.toJson());
    _rebuild();
  }

  void setOptions(DraftOptions o) {
    options = o;
    store.writeJson('options', o.toJson());
    _rebuild();
  }

  /// A whole code list (loaded from a file, or the standard one)
  void setLibrary(CodeLibrary l, {String label = 'code list'}) => _change(label, library: l);

  void resetLibrary() => setLibrary(CodeLibrary.defaults(), label: 'standard code list');

  /// Adds a code, or replaces [replacing] (its old code) with [c]
  void saveCode(FeatureCode c, {String? replacing}) {
    final codes = library.all.where((x) => x.code != (replacing ?? c.code).toUpperCase() && x.code != c.code).toList()
      ..add(c);
    _change(replacing == null ? 'add code ${c.code}' : 'change code ${c.code}', library: CodeLibrary(codes));
  }

  void deleteCode(String code) =>
      _change('remove code $code', library: CodeLibrary(library.all.where((c) => c.code != code.toUpperCase())));

  /// Changes one point's code (from the points list or the drawing) and redraws
  void setCode(int index, String code) {
    final c = code.trim();
    if (c == points[index].code) return;
    _change('code of point ${points[index].id}', points: [...points]..[index] = points[index].copyWith(code: c));
  }

  /// Changes the first word of every point coded [from] to [to]: "XX" → "TR". The words after it stay.
  int replaceCode(String from, String to) {
    final f = from.toUpperCase();
    var n = 0;
    final next = [
      for (final p in points)
        () {
          final words = p.code.trim().split(RegExp(r'\s+'));
          if (words.isEmpty || words.first.toUpperCase() != f) return p;
          n++;
          return p.copyWith(code: [to.trim(), ...words.skip(1)].join(' '));
        }(),
    ];
    if (n > 0) _change('$from → $to on $n point${n == 1 ? '' : 's'}', points: next);
    return n;
  }

  /// Puts back the file's code of every changed point
  void revertCodes() {
    if (changedCodes == 0) return;
    _change(
      'back to the file\'s codes',
      points: [for (var i = 0; i < points.length; i++) points[i].copyWith(code: _fileCodes[i])],
    );
  }

  void undo() => _travel(_undo, _redo);
  void redo() => _travel(_redo, _undo);

  void _travel(List<_Step> from, List<_Step> to) {
    if (from.isEmpty) return;
    final step = from.removeLast();
    to.add(_Step(step.label, points, library));
    _apply(step.points, step.library);
  }

  void _change(String label, {List<SurveyPoint>? points, CodeLibrary? library}) {
    _undo.add(_Step(label, this.points, this.library));
    if (_undo.length > _historySize) _undo.removeAt(0);
    _redo.clear();
    _apply(points ?? this.points, library ?? this.library);
  }

  void _apply(List<SurveyPoint> p, CodeLibrary l) {
    if (!identical(l, library)) store.write('codes', l.toJsonString());
    points = p;
    library = l;
    if (drawing != null || points.isNotEmpty) {
      _rebuild();
    } else {
      notifyListeners();
    }
  }

  void toggleLayer(String name) {
    if (!hiddenLayers.remove(name)) hiddenLayers.add(name);
    notifyListeners();
  }

  void selectProblem(int i) {
    selectedProblem = i;
    final p = drawing!.problems[i];
    if (p.at != null) focus.value = FocusRequest(p.at!, p.pointIds);
    notifyListeners();
  }

  void showPoint(SurveyPoint p) {
    selectedProblem = null;
    final i = points.indexOf(p);
    picked = i < 0 ? null : i;
    focus.value = FocusRequest(Vertex(p.e, p.n, p.z ?? 0), [p.id]);
    notifyListeners();
  }

  /// A point clicked on the drawing (null: clicked away from every point)
  void pick(int? index) {
    picked = index;
    notifyListeners();
  }

  void _rebuild() {
    drawing = buildDrawing(points, library, options);
    sheet = buildSheet(drawing!, sheetInfo);
    selectedProblem = null;
    notifyListeners();
  }

  /// The DXF file's text
  String dxf() => writeDxf(drawing!, sheet: showSheet ? sheet : null);

  /// The sheet as a PDF at scale
  Future<Uint8List> pdf(PdfFonts fonts) => writePdf(drawing!, sheet!, fonts, title: sheetInfo.title);

  /// The UTM zone for Google Earth, remembered (Pakistan: 41 to 44; Lahore and Islamabad 43)
  int get kmlZone => (store.readJson('kml')?['zone'] as int?) ?? 43;
  bool get kmlNorth => (store.readJson('kml')?['north'] as bool?) ?? true;

  /// The drawing for Google Earth
  String kml({required int zone, required bool north}) {
    store.writeJson('kml', {'zone': zone, 'north': north});
    return writeKml(
      drawing!,
      zone: zone,
      north: north,
      title: sheetInfo.title.isEmpty ? (fileName ?? '') : sheetInfo.title,
    );
  }

  /// "survey.csv" → "survey.kml"
  String get kmlName => dxfName.replaceFirst(RegExp(r'\.dxf$'), '.kml');

  /// "survey.csv" → "survey.pdf"
  String get pdfName => dxfName.replaceFirst(RegExp(r'\.dxf$'), '.pdf');

  /// The points as CSV, with their corrected codes: Point,Easting,Northing,Level,Code
  String pointsCsv() {
    String cell(String s) => s.contains(RegExp(r'[,"\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    final b = StringBuffer('Point,Easting,Northing,Level,Code\r\n');
    for (final p in points) {
      b.write(
        '${cell(p.id)},${p.e.toStringAsFixed(4)},${p.n.toStringAsFixed(4)},${p.z?.toStringAsFixed(4) ?? ''},${cell(p.code)}\r\n',
      );
    }
    return b.toString();
  }

  /// "survey.csv" → "survey-corrected.csv"
  String get csvName {
    final n = fileName ?? 'points';
    final dot = n.lastIndexOf('.');
    return '${dot > 0 ? n.substring(0, dot) : n}-corrected.csv';
  }

  /// "survey.csv" → "survey.dxf"
  String get dxfName {
    final n = fileName ?? 'drawing';
    final dot = n.lastIndexOf('.');
    return '${dot > 0 ? n.substring(0, dot) : n}.dxf';
  }
}
