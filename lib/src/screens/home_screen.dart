// The window: a navy bar with the file and the actions, the drawing, and the side panel. Before a
// file is open it shows how to start, with the sample survey to try.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../engine/codes.dart';
import '../engine/drawing.dart';
import '../state/app_state.dart';
import '../state/files.dart';
import '../ui/drawing_view.dart';
import '../ui/theme.dart';
import 'columns_dialog.dart';
import 'options_dialog.dart';
import 'side_panel.dart';

const surveyExtensions = ['csv', 'txt', 'prn', 'xlsx', 'xls', 'asc', 'pts'];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.state, required this.files});
  final AppState state;
  final FileIo files;

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

  Future<void> _open(BuildContext context) async {
    final picked = await files.open(label: 'Survey points', extensions: surveyExtensions);
    if (picked == null || !context.mounted) return;
    await _openBytes(context, picked.$1, picked.$2);
  }

  Future<void> _sample(BuildContext context) async {
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
    state.setLibrary(l);
    _message(context, '${l.all.length} codes loaded from ${picked.$1}.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final d = state.drawing;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyO, control: true): () => _open(context),
            if (d != null) const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(context),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Column(
                children: [
                  _TopBar(
                    state: state,
                    onOpen: () => _open(context),
                    onSample: () => _sample(context),
                    onOptions: () => _options(context),
                    onSave: () => _save(context),
                  ),
                  Expanded(
                    child: d == null
                        ? _Welcome(onOpen: () => _open(context), onSample: () => _sample(context))
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: DrawingView(state: state)),
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
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.state,
    required this.onOpen,
    required this.onSample,
    required this.onOptions,
    required this.onSave,
  });
  final AppState state;
  final VoidCallback onOpen, onSample, onOptions, onSave;

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
            _BarButton(Icons.tune, '1:${state.options.scale}', 'Drawing settings: scale, text, labels', onOptions),
            _BarButton(Icons.close, 'Close', 'Close this survey', state.close),
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
                'CSV, TXT or Excel (.xlsx): point, easting, northing, level and code',
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
