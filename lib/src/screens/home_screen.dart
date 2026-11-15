// The window: a navy bar with the file and the actions, the drawing, and the side panel. Before a
// file is open it shows how to start, with the sample survey to try.
import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../engine/codes.dart';
import '../engine/drawing.dart';
import '../engine/pdf.dart';
import '../state/app_state.dart';
import '../state/files.dart';
import '../ui/drawing_view.dart';
import '../ui/theme.dart';
import 'columns_dialog.dart';
import 'edits.dart';
import 'kml_dialog.dart';
import 'options_dialog.dart';
import 'sheet_dialog.dart';
import 'side_panel.dart';

/// Survey files: tables, and total station files (Leica GSI, Sokkia SDR, Nikon RAW)
const surveyExtensions = ['csv', 'txt', 'prn', 'xlsx', 'xls', 'asc', 'pts', 'gsi', 'sdr', 'raw'];

/// A keyboard action that steps aside while a text box has the focus, so Ctrl+Z there undoes typing
class _AppAction<T extends Intent> extends CallbackAction<T> {
  _AppAction(void Function() run) : super(onInvoke: (_) => run());

  @override
  bool isEnabled(T intent) => FocusManager.instance.primaryFocus?.context?.widget is! EditableText;
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state, required this.files, this.dropFiles = false});
  final AppState state;
  final FileIo files;

  /// Files can be dragged onto the window (Windows; off in tests, which have no drop support)
  final bool dropFiles;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppState get state => widget.state;
  FileIo get files => widget.files;
  bool _dragging = false;

  void _message(BuildContext context, String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: error ? Tone.error : null,
          duration: Duration(seconds: error ? 8 : 4),
        ),
      );
  }

  Future<void> _openBytes(BuildContext context, String name, Uint8List bytes) async {
    final OpenedFile f;
    try {
      f = AppState.read(name, bytes);
    } on FormatException catch (e) {
      _message(context, e.message, error: true);
      return;
    }
    if (!context.mounted) return;
    final m = await showColumnsDialog(context, f);
    if (m != null) state.open(f, m);
  }

  /// Before the survey is closed or replaced: corrected codes not saved yet are offered for saving.
  /// False: stay.
  Future<bool> _leave(BuildContext context) async {
    final n = state.changedCodes;
    if (n == 0) return true;
    final r = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$n corrected code${n == 1 ? '' : 's'} not saved'),
        content: const SizedBox(
          width: 420,
          child: Text(
            'Save the points with their corrected codes as a CSV, so the corrections aren\'t lost? '
            'A saved DXF already has them in the drawing.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'stay'), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, 'drop'), child: const Text('Don\'t save')),
          FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save points…')),
        ],
      ),
    );
    if (r == 'drop') return true;
    if (r == 'save' && context.mounted) return _savePoints(context);
    return false;
  }

  Future<void> _close(BuildContext context) async {
    if (await _leave(context)) state.close();
  }

  Future<bool> _savePoints(BuildContext context) async {
    final path = await files.save(
      suggestedName: state.csvName,
      label: 'Survey points (CSV)',
      extensions: const ['csv'],
      bytes: utf8.encode(state.pointsCsv()),
    );
    if (path == null) return false;
    if (context.mounted) _message(context, 'Points saved to $path with their corrected codes.');
    return true;
  }

  Future<void> _dropped(BuildContext context, DropDoneDetails d) async {
    setState(() => _dragging = false);
    if (d.files.isEmpty) return;
    final f = d.files.first;
    if (!surveyExtensions.contains(f.name.split('.').last.toLowerCase())) {
      _message(context, '${f.name} isn\'t a survey file. Drop a CSV, TXT or Excel (.xlsx) file.', error: true);
      return;
    }
    if (!await _leave(context) || !context.mounted) return;
    final bytes = await f.readAsBytes();
    if (context.mounted) await _openBytes(context, f.name, bytes);
  }

  Future<void> _open(BuildContext context) async {
    if (!await _leave(context) || !context.mounted) return;
    final picked = await files.open(label: 'Survey points', extensions: surveyExtensions);
    if (picked == null || !context.mounted) return;
    await _openBytes(context, picked.$1, picked.$2);
  }

  Future<void> _sample(BuildContext context) async {
    if (!await _leave(context) || !context.mounted) return;
    final data = await rootBundle.load('assets/samples/sample-survey.csv');
    if (!context.mounted) return;
    await _openBytes(context, 'sample-survey.csv', data.buffer.asUint8List());
  }

  Future<void> _save(BuildContext context) async {
    final path = await files.save(
      suggestedName: state.dxfName,
      label: 'AutoCAD drawing (DXF)',
      extensions: const ['dxf'],
      bytes: ascii.encode(state.dxf()),
    );
    if (path != null && context.mounted) {
      _message(context, 'Saved $path. Open it in AutoCAD, BricsCAD or any CAD program.');
    }
  }

  Future<void> _sheet(BuildContext context) async {
    final i = await showSheetDialog(context, state.sheetInfo, state.drawing!);
    if (i != null) state.setSheetInfo(i);
  }

  Future<void> _savePdf(BuildContext context) async {
    final fonts = PdfFonts(
      await rootBundle.load('assets/fonts/Inter_400Regular.ttf'),
      await rootBundle.load('assets/fonts/Inter_700Bold.ttf'),
    );
    final bytes = await state.pdf(fonts);
    final path = await files.save(suggestedName: state.pdfName, label: 'PDF', extensions: const ['pdf'], bytes: bytes);
    if (path != null && context.mounted) {
      final s = state.sheet!;
      _message(
        context,
        'Saved $path: ${s.label}. Print it at 100 % (actual size) to keep the scale.'
        '${s.fits ? '' : ' The survey doesn\'t fit the sheet: ${s.advice}'}',
      );
    }
  }

  Future<void> _saveKml(BuildContext context) async {
    final z = await showKmlDialog(context, state.kmlZone, state.kmlNorth);
    if (z == null || !context.mounted) return;
    final path = await files.save(
      suggestedName: state.kmlName,
      label: 'Google Earth (KML)',
      extensions: const ['kml'],
      bytes: utf8.encode(state.kml(zone: z.$1, north: z.$2)),
    );
    if (path != null && context.mounted) _message(context, 'Saved $path. Open it in Google Earth.');
  }

  Future<void> _options(BuildContext context) async {
    final o = await showOptionsDialog(context, state.options);
    if (o != null) state.setOptions(o);
  }

  Future<void> _saveCodes(BuildContext context) async {
    final path = await files.save(
      suggestedName: 'auto-draft-codes.json',
      label: 'Auto Draft code list',
      extensions: const ['json'],
      bytes: utf8.encode(state.library.toJsonString()),
    );
    if (path != null && context.mounted) {
      _message(context, 'Code list saved to $path. Share it so the whole team uses the same codes.');
    }
  }

  Future<void> _loadCodes(BuildContext context) async {
    final picked = await files.open(label: 'Auto Draft code list', extensions: const ['json']);
    if (picked == null || !context.mounted) return;
    final l = CodeLibrary.fromJsonString(utf8.decode(picked.$2, allowMalformed: true));
    if (l == null) {
      _message(context, '${picked.$1} isn\'t an Auto Draft code list.', error: true);
      return;
    }
    state.setLibrary(l, label: 'code list ${picked.$1}');
    sayDone(context, state, '${l.all.length} codes loaded from ${picked.$1}.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final d = state.drawing;
        Widget body = Column(
          children: [
            _TopBar(
              state: state,
              onOpen: () => _open(context),
              onSample: () => _sample(context),
              onOptions: () => _options(context),
              onSave: () => _save(context),
              onSavePoints: () => _savePoints(context),
              onSheet: () => _sheet(context),
              onSavePdf: () => _savePdf(context),
              onSaveKml: () => _saveKml(context),
              onClose: () => _close(context),
            ),
            Expanded(
              child: d == null
                  ? _Welcome(onOpen: () => _open(context), onSample: () => _sample(context))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: DrawingView(state: state, onEditPoint: (i) => editPointCode(context, state, i)),
                        ),
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: 400,
                          child: Material(
                            color: Colors.white,
                            child: SidePanel(
                              state: state,
                              onSaveCodes: () => _saveCodes(context),
                              onLoadCodes: () => _loadCodes(context),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            if (d != null) _StatusBar(state: state, drawing: d),
          ],
        );
        if (widget.dropFiles) {
          body = DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (e) => _dropped(context, e),
            child: Stack(
              children: [
                body,
                if (_dragging) const Positioned.fill(child: _DropHint()),
              ],
            ),
          );
        }
        return Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyZ, control: true): _UndoIntent(),
            SingleActivator(LogicalKeyboardKey.keyY, control: true): _RedoIntent(),
            SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _RedoIntent(),
          },
          child: Actions(
            actions: {
              _UndoIntent: _AppAction<_UndoIntent>(state.undo),
              _RedoIntent: _AppAction<_RedoIntent>(state.redo),
            },
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyO, control: true): () => _open(context),
                if (d != null) const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(context),
              },
              child: Focus(autofocus: true, child: Scaffold(body: body)),
            ),
          ),
        );
      },
    );
  }
}

class _DropHint extends StatelessWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      color: BrandColors.navy.withValues(alpha: 0.82),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        decoration: BoxDecoration(
          border: Border.all(color: BrandColors.gold, width: 2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.file_download_outlined, color: BrandColors.goldLight, size: 46),
            SizedBox(height: 12),
            Text(
              'Drop the survey file to draw it',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 6),
            Text('CSV, TXT or Excel (.xlsx)', style: TextStyle(color: Color(0xFFB8C4D8))),
          ],
        ),
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.state,
    required this.onOpen,
    required this.onSample,
    required this.onOptions,
    required this.onSave,
    required this.onSavePoints,
    required this.onSheet,
    required this.onSavePdf,
    required this.onSaveKml,
    required this.onClose,
  });
  final AppState state;
  final VoidCallback onOpen, onSample, onOptions, onSave, onSavePoints, onClose, onSheet, onSavePdf, onSaveKml;

  @override
  Widget build(BuildContext context) {
    final has = state.hasDrawing;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [BrandColors.navy, BrandColors.navyLight])),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset('assets/brand/icon-512.png', width: 36, height: 36),
          ),
          const SizedBox(width: 12),
          const Text(
            appName,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
          ),
          if (state.fileName != null) ...[
            const SizedBox(width: 14),
            Container(width: 1, height: 26, color: Colors.white24),
            const SizedBox(width: 14),
            const Icon(Icons.description_outlined, color: BrandColors.goldLight, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                state.fileName!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ] else
            const Spacer(),
          if (state.fileName != null) const Spacer(),
          _BarButton(Icons.folder_open_outlined, 'Open', 'Open a survey file (Ctrl+O)', onOpen),
          if (!has) _BarButton(Icons.science_outlined, 'Sample', 'Try the sample survey', onSample),
          if (has) ...[
            IconButton(
              tooltip: state.canUndo ? 'Undo: ${state.undoLabel} (Ctrl+Z)' : 'Nothing to undo',
              color: Colors.white,
              disabledColor: Colors.white30,
              onPressed: state.canUndo ? state.undo : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: state.canRedo ? 'Redo: ${state.redoLabel} (Ctrl+Y)' : 'Nothing to redo',
              color: Colors.white,
              disabledColor: Colors.white30,
              onPressed: state.canRedo ? state.redo : null,
              icon: const Icon(Icons.redo),
            ),
            const SizedBox(width: 4),
            _BarButton(Icons.tune, '1:${state.options.scale}', 'Drawing settings: scale, text, labels', onOptions),
            _BarButton(
              state.sheet?.fits == false ? Icons.warning_amber_rounded : Icons.crop_landscape,
              state.sheet?.paper.label ?? 'Sheet',
              'Sheet and title block: paper, firm, title, date',
              onSheet,
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (v) => switch (v) {
                'points' => onSavePoints(),
                'pdf' => onSavePdf(),
                'kml' => onSaveKml(),
                'revert' => state.revertCodes(),
                _ => onClose(),
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: const Text('Save PDF'),
                    subtitle: Text(state.sheet == null ? '' : 'The sheet, ${state.sheet!.label}'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'kml',
                  child: ListTile(
                    leading: Icon(Icons.public),
                    title: Text('Save KML (Google Earth)'),
                    subtitle: Text('Lines and points on the map'),
                  ),
                ),
                PopupMenuItem(
                  value: 'points',
                  child: ListTile(
                    leading: const Icon(Icons.table_view_outlined),
                    title: const Text('Save points (CSV)'),
                    subtitle: Text(
                      state.changedCodes == 0
                          ? 'Point, E, N, Z, code'
                          : 'With ${state.changedCodes} corrected code${state.changedCodes == 1 ? '' : 's'}',
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'revert',
                  enabled: state.changedCodes > 0,
                  child: const ListTile(leading: Icon(Icons.restore), title: Text('Back to the file\'s codes')),
                ),
                const PopupMenuItem(
                  value: 'close',
                  child: ListTile(leading: Icon(Icons.close), title: Text('Close this survey')),
                ),
              ],
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: goldButton(),
              onPressed: onSave,
              icon: const Icon(Icons.save_alt, size: 19),
              label: const Text('Save DXF'),
            ),
          ],
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton(this.icon, this.label, this.tip, this.onTap);
  final IconData icon;
  final String label, tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 19),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
  );
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state, required this.drawing});
  final AppState state;
  final Drawing drawing;

  @override
  Widget build(BuildContext context) {
    final d = drawing;
    final checks = d.problems.where((p) => p.severity != Severity.info).length;
    Widget item(String text) => Padding(
      padding: const EdgeInsets.only(right: 18),
      child: Text(text, style: const TextStyle(fontSize: 12.5, color: Tone.muted)),
    );
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Tone.line)),
      ),
      child: Row(
        children: [
          item('${d.points.length} points'),
          item('${d.lines.length} lines'),
          item('${d.symbols.length} symbols'),
          item('${d.layers.length} layers'),
          item('Scale 1:${d.options.scale}${d.options.lines3d ? ' · 3D lines' : ''}'),
          if (state.sheet != null)
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Text(
                state.sheet!.fits ? 'Sheet ${state.sheet!.label}' : 'Doesn\'t fit ${state.sheet!.label}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: state.sheet!.fits ? Tone.muted : Tone.warning,
                  fontWeight: state.sheet!.fits ? null : FontWeight.w700,
                ),
              ),
            ),
          const Spacer(),
          Icon(
            checks == 0 ? Icons.check_circle : Icons.warning_amber_rounded,
            size: 15,
            color: checks == 0 ? Tone.ok : Tone.warning,
          ),
          const SizedBox(width: 6),
          Text(
            checks == 0 ? 'Ready to save' : '$checks thing${checks == 1 ? '' : 's'} to check',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: checks == 0 ? Tone.ok : Tone.warning),
          ),
        ],
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onOpen, required this.onSample});
  final VoidCallback onOpen, onSample;

  @override
  Widget build(BuildContext context) {
    Widget step(String n, String title, String text) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Tone.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: BrandColors.navy,
              child: Text(
                n,
                style: const TextStyle(color: BrandColors.goldLight, fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(color: Tone.muted, height: 1.4)),
          ],
        ),
      ),
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset('assets/brand/icon-512.png', width: 88, height: 88),
              ),
              const SizedBox(height: 20),
              const Text(
                'From field points to a finished drawing',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const Text(
                'Open the day\'s survey. Auto Draft joins the lines by their codes, places the symbols, writes the levels and puts '
                'everything on its own layer, ready for AutoCAD.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Tone.muted, height: 1.45),
              ),
              const SizedBox(height: 26),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    style: goldButton().copyWith(
                      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 26, vertical: 18)),
                    ),
                    onPressed: onOpen,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open a survey file'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18)),
                    onPressed: onSample,
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Try the sample survey'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'CSV, TXT, Excel (.xlsx) or a total station file (Leica GSI, Sokkia SDR, Nikon RAW)',
                style: TextStyle(color: Tone.muted, fontSize: 13),
              ),
              const SizedBox(height: 34),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    step(
                      '1',
                      'Code in the field',
                      'RE1 for road edge 1, WL1 for a wall, TR for a tree. Add ST, END, CLS, ARC or RECT to steer a line.',
                    ),
                    const SizedBox(width: 12),
                    step(
                      '2',
                      'Check the drawing',
                      'Auto Draft lists anything doubtful: unknown codes, lines with one point, jumps. Click to see it, fix the code.',
                    ),
                    const SizedBox(width: 12),
                    step(
                      '3',
                      'Save the DXF',
                      'Layers, colours, symbols and levels, at real coordinates. Opens in AutoCAD, LT, Civil 3D and BricsCAD.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
