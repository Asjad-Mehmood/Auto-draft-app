// Reads what the surveyor typed in the code field.
//
//   "RE1"          road edge, line number 1
//   "RE1 ST"       start a new road edge 1 here
//   "BLD2 CLS"     building 2, close the shape at this point
//   "RE1 KB1"      the point is on two lines: road edge 1 and kerb 1
//   "TR"           a tree
//   "WL3 ARC"      wall 3, a curve starts here (it ends at "WL3 EARC")
//   "BLD4 RECT"    the third corner of building 4: the fourth corner is added
//
// A code that is in the code list may end with a line number (RE1, RE2…); a word that is neither
// a code nor a control word is kept as a remark. Upper or lower case, separated by spaces, commas,
// semicolons or slashes.
import 'codes.dart';

class FeatureRef {
  FeatureRef(this.feature, this.number);

  final FeatureCode feature;

  /// The line number written after the code: RE1 → 1, RE → 0
  final int number;
  final Set<Control> controls = {};

  /// The key that keeps separate lines apart: "RE#1"
  String get key => '${feature.code}#$number';
}

class ParsedCode {
  ParsedCode(this.refs, {this.unknown = '', this.remarks = const [], this.strayControls = const []});

  /// The features this point belongs to, in the order written
  final List<FeatureRef> refs;

  /// The first word when it isn't a code in the list ("XYZ"); empty otherwise
  final String unknown;

  /// Words that are neither codes nor control words
  final List<String> remarks;

  /// Control words written before any code ("ST RE1"), which can't apply to anything
  final List<String> strayControls;

  bool get isEmpty => refs.isEmpty && unknown.isEmpty;
}

final _split = RegExp(r'[\s,;/]+');
final _codeAndNumber = RegExp(r'^([A-Z][A-Z0-9]*?)(\d+)$');

ParsedCode parseCode(String text, CodeLibrary library) {
  final words = text.trim().toUpperCase().split(_split).where((w) => w.isNotEmpty).toList();
  final refs = <FeatureRef>[];
  final remarks = <String>[];
  final stray = <String>[];
  var unknown = '';
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final control = controlWords[w];
    if (control != null) {
      if (refs.isEmpty) {
        stray.add(w);
      } else {
        refs.last.controls.add(control);
      }
      continue;
    }
    final ref = _feature(w, library);
    if (ref != null) {
      refs.add(ref);
    } else if (i == 0) {
      unknown = w;
    } else {
      remarks.add(w);
    }
  }
  return ParsedCode(refs, unknown: unknown, remarks: remarks, strayControls: stray);
}

/// "RE12" → road edge 12, when RE is in the list. A code that itself ends in digits ("TB2")
/// wins when it is in the list.
FeatureRef? _feature(String word, CodeLibrary library) {
  final whole = library[word];
  if (whole != null) return FeatureRef(whole, 0);
  final m = _codeAndNumber.firstMatch(word);
  if (m == null) return null;
  // try the longest code first: "TB21" is TB2 + 1 when TB2 is a code, else TB + 21
  final digits = m.group(2)!;
  for (var cut = 1; cut <= digits.length; cut++) {
    final code = word.substring(0, word.length - cut);
    final f = library[code];
    if (f != null) return FeatureRef(f, int.parse(word.substring(word.length - cut)));
  }
  return null;
}
