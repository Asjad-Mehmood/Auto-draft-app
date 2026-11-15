// What the window shows: the open survey, how its columns are read, the drawing settings, the
// code list and the drawing made from them. A change to any of them redraws at once.
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../engine/builder.dart';
import '../engine/codes.dart';
import '../engine/drawing.dart';
import '../engine/dxf.dart';
import '../engine/import.dart';
import '../engine/point.dart';
import 'store.dart';

/// A file that was read, waiting for its columns to be confirmed
class OpenedFile {
  const OpenedFile(this.name, this.table, this.guess);
  final String name;
  final Table table;
  final ColumnMap guess;
}

/// Where the drawing should look: a problem or a point picked in the side panel
class FocusRequest {
  const FocusRequest(this.at, this.pointIds);
  final Vertex at;
  final List<String> pointIds;
}

class AppState extends ChangeNotifier {
  AppState(this.store) {
    options = DraftOptions.fromJson(store.readJson('options'));
    final saved = store.read('codes');
    library = (saved == null ? null : CodeLibrary.fromJsonString(saved)) ?? CodeLibrary.defaults();
  }

  final Store store;
  late DraftOptions options;
  late CodeLibrary library;

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
    skipped = r.skipped;
    hiddenLayers.clear();
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
    selectedProblem = null;
    focus.value = null;
    notifyListeners();
  }

  void setOptions(DraftOptions o) {
    options = o;
    store.writeJson('options', o.toJson());
    _rebuild();
  }

  void setLibrary(CodeLibrary l) {
    library = l;
    store.write('codes', l.toJsonString());
    _rebuild();
  }

  void resetLibrary() => setLibrary(CodeLibrary.defaults());

  /// Changes one point's code (from the points list) and redraws
  void setCode(int index, String code) {
    points = [...points]..[index] = points[index].copyWith(code: code.trim());
    _rebuild();
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
    focus.value = FocusRequest(Vertex(p.e, p.n, p.z ?? 0), [p.id]);
    notifyListeners();
  }

  void _rebuild() {
    drawing = buildDrawing(points, library, options);
    selectedProblem = null;
    notifyListeners();
  }

  /// The DXF file's text
  String dxf() => writeDxf(drawing!);

  /// "survey.csv" → "survey.dxf"
  String get dxfName {
    final n = fileName ?? 'drawing';
    final dot = n.lastIndexOf('.');
    return '${dot > 0 ? n.substring(0, dot) : n}.dxf';
  }
}
