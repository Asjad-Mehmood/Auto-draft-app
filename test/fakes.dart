import 'dart:convert';
import 'dart:typed_data';

import 'package:auto_draft/src/app.dart';
import 'package:auto_draft/src/state/app_state.dart';
import 'package:auto_draft/src/state/files.dart';
import 'package:auto_draft/src/state/store.dart';
import 'package:flutter/widgets.dart';

/// Files to "open" are queued; "saved" files are kept
class FakeFiles implements FileIo {
  final toOpen = <(String, Uint8List)>[];
  final saved = <String, List<int>>{};

  void queue(String name, String text) => toOpen.add((name, Uint8List.fromList(utf8.encode(text))));

  @override
  Future<(String, Uint8List)?> open({required String label, required List<String> extensions}) async =>
      toOpen.isEmpty ? null : toOpen.removeAt(0);

  @override
  Future<String?> save({
    required String suggestedName,
    required String label,
    required List<String> extensions,
    required List<int> bytes,
  }) async {
    saved[suggestedName] = bytes;
    return 'C:\\Users\\surveyor\\Documents\\$suggestedName';
  }
}

class Harness {
  Harness({Store? store}) : state = AppState(store ?? Store.memory());
  final AppState state;
  final files = FakeFiles();
  Widget get app => AutoDraftApp(state: state, files: files);
}

/// A survey with mistakes in it, for the problem list
const surveyWithMistakes = '''Point,Easting,Northing,Level,Code
1,436200,3487400,214.60,RE1
2,436220,3487400,214.56,RE1
3,436240,3487400,214.52,RE1
4,436400,3487400,214.40,RE1
5,436260,3487392.7,214.30,RE2
6,436280,3487392.7,214.26,RE2
7,436210,3487410,214.10,TR
8,436230,3487412,214.15,XX
9,436250,3487415,214.12,FN1
10,436222,3487405,0,SP
''';
