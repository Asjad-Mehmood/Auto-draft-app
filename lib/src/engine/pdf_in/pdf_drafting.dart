// PDF to drawing: open a PDF, choose a page, and get it redrawn as a CAD drawing (see rebuild.dart),
// ready to save as a DXF. Plain Dart: the app, the command line and the tests use this.
import 'dart:typed_data';

import 'cad.dart';
import 'dxf2000.dart';
import 'pdf_content.dart';
import 'pdf_file.dart';
import 'rebuild.dart';

export 'cad.dart';
export 'pdf_file.dart' show PdfReadError;
export 'rebuild.dart' show PdfDraftOptions, PageDraft;

class PdfDrawingFile {
  PdfDrawingFile._(this._file);
  final PdfFile _file;
  final _pages = <int, PageContent>{};

  /// Throws [PdfReadError] with a message for the person when it can't be read
  static PdfDrawingFile open(Uint8List bytes) => PdfDrawingFile._(PdfFile.parse(bytes));

  int get pageCount => _file.pages.length;

  /// The PDF's own layer names, when it has them
  List<String> get layerNames => _file.layerNames.values.toList();

  /// Page [index] (from 0): its size in millimetres
  ({double width, double height}) pageSize(int index) {
    final c = content(index);
    return (width: c.width * 25.4 / 72, height: c.height * 25.4 / 72);
  }

  PageContent content(int index) => _pages.putIfAbsent(index, () => readPage(_file.pages[index]));

  /// Redraws page [index]; with no scale given, the scale its dimensions show is used when it has
  /// any (see [PageDraft.suggestedScale]), else millimetres as printed
  PageDraft draft(int index, {PdfDraftOptions options = const PdfDraftOptions(), bool autoScale = false}) {
    final first = draftPage(content(index), options);
    if (autoScale && options.scale == null && first.suggestedScale != null && first.suggestedScale! > 1) {
      return draftPage(
        content(index),
        PdfDraftOptions(
          scale: first.suggestedScale,
          useLayers: options.useLayers,
          findDimensions: options.findDimensions,
          findHatches: options.findHatches,
        ),
      );
    }
    return first;
  }
}

String pdfDrawingToDxf(CadDrawing d) => writeDxf2000(d);
