// Opening and saving files through Windows' own dialogs. Behind an interface so the tests can
// open and save without a dialog.
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

abstract class FileIo {
  /// The file picked to open (name and bytes), or null when cancelled
  Future<(String, Uint8List)?> open({required String label, required List<String> extensions});

  /// Saves bytes where the person chooses; the path, or null when cancelled
  Future<String?> save({
    required String suggestedName,
    required String label,
    required List<String> extensions,
    required List<int> bytes,
  });
}

class DialogFileIo implements FileIo {
  @override
  Future<(String, Uint8List)?> open({required String label, required List<String> extensions}) async {
    final f = await openFile(
      acceptedTypeGroups: [XTypeGroup(label: label, extensions: extensions)],
    );
    if (f == null) return null;
    return (f.name, await f.readAsBytes());
  }

  @override
  Future<String?> save({
    required String suggestedName,
    required String label,
    required List<String> extensions,
    required List<int> bytes,
  }) async {
    final loc = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [XTypeGroup(label: label, extensions: extensions)],
    );
    if (loc == null) return null;
    var path = loc.path;
    if (!extensions.any((e) => path.toLowerCase().endsWith('.$e'))) path = '$path.${extensions.first}';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }
}
