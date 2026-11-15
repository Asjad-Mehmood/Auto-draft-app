// Beside the drawing: the problems found (click one to see it), the layers (switch them off in
// the preview), the points (find one, correct its code) and the code list.
import 'package:flutter/material.dart';

import '../engine/codes.dart';
import '../engine/drawing.dart';
import '../engine/symbols.dart';
import '../state/app_state.dart';
import '../ui/aci.dart';
import '../ui/theme.dart';

class SidePanel extends StatelessWidget {
  const SidePanel({super.key, required this.state, required this.onSaveCodes, required this.onLoadCodes});
  final AppState state;
  final VoidCallback onSaveCodes;
  final VoidCallback onLoadCodes;

  @override
  Widget build(BuildContext context) {
    final d = state.drawing!;
    final warnings = d.problems.where((p) => p.severity != Severity.info).length;
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelColor: Tone.muted,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Problems'),
                      const SizedBox(width: 6),
                      _Count(
                        d.problems.length,
                        warnings > 0 ? Tone.warning : (d.problems.isEmpty ? Tone.ok : Tone.info),
                      ),
                    ],
                  ),
                ),
                const Tab(text: 'Layers'),
                const Tab(text: 'Points'),
                const Tab(text: 'Codes'),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: TabBarView(
              children: [
                _Problems(state),
                _Layers(state),
                _Points(state),
                _Codes(state, onSave: onSaveCodes, onLoad: onLoadCodes),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n, this.color);
  final int n;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Text(
      '$n',
      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
    ),
  );
}

// ------------------------------------------------------------------ problems

class _Problems extends StatelessWidget {
  const _Problems(this.state);
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final d = state.drawing!;
    if (d.problems.isEmpty && state.skipped.isEmpty) {
      return const _Empty(
        Icons.verified_outlined,
        'No problems found',
        'Every code was understood and every line has its points. Check the drawing, then save the DXF.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (state.skipped.isNotEmpty)
          _ProblemCard(
            severity: Severity.warning,
            title: '${state.skipped.length} line${state.skipped.length == 1 ? '' : 's'} of the file skipped',
            detail:
                state.skipped.take(6).map((s) => 'Line ${s.$1}: ${s.$2}').join('\n') +
                (state.skipped.length > 6 ? '\n…' : ''),
          ),
        for (var i = 0; i < d.problems.length; i++)
          _ProblemCard(
            severity: d.problems[i].severity,
            title: d.problems[i].title,
            detail: d.problems[i].detail,
            selected: state.selectedProblem == i,
            onTap: d.problems[i].at == null ? null : () => state.selectProblem(i),
          ),
      ],
    );
  }
}

class _ProblemCard extends StatelessWidget {
  const _ProblemCard({
    required this.severity,
    required this.title,
    required this.detail,
    this.selected = false,
    this.onTap,
  });
  final Severity severity;
  final String title, detail;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (color, icon, word) = switch (severity) {
      Severity.error => (Tone.error, Icons.error_outline, 'Error'),
      Severity.warning => (Tone.warning, Icons.warning_amber_rounded, 'Check'),
      Severity.info => (Tone.info, Icons.info_outline, 'Note'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? color.withValues(alpha: 0.07) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? color : Tone.line, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20, semanticLabel: word),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      const SizedBox(height: 4),
                      Text(detail, style: const TextStyle(color: Tone.muted, fontSize: 12.5, height: 1.35)),
                      if (onTap != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Show on the drawing',
                          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ layers

class _Layers extends StatelessWidget {
  const _Layers(this.state);
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final d = state.drawing!;
    int count(String layer) =>
        d.lines.where((l) => l.layer == layer).length +
        d.symbols.where((s) => s.layer == layer).length +
        d.texts.where((t) => t.layer == layer).length +
        (layer == Layers.points.name ? d.points.length : 0);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Switch a layer off to hide it here. The DXF keeps every layer.',
            style: TextStyle(color: Tone.muted, fontSize: 12.5),
          ),
        ),
        for (final l in d.layers)
          CheckboxListTile(
            dense: true,
            value: !state.hiddenLayers.contains(l.name),
            onChanged: (_) => state.toggleLayer(l.name),
            controlAffinity: ListTileControlAffinity.leading,
            title: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: aciColor(l.color),
                    border: Border.all(color: Tone.line),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(l.name, style: mono.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            subtitle: Text(
              '${l.description.isEmpty ? '' : '${l.description} · '}${count(l.name)} item${count(l.name) == 1 ? '' : 's'}'
              '${l.lineType == 'CONTINUOUS' ? '' : ' · ${l.lineType.toLowerCase()}'}',
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ points

class _Points extends StatefulWidget {
  const _Points(this.state);
  final AppState state;

  @override
  State<_Points> createState() => _PointsState();
}

class _PointsState extends State<_Points> {
  String _find = '';

  Future<void> _edit(int index) async {
    final p = widget.state.points[index];
    final c = TextEditingController(text: p.code);
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Code of point ${p.id}'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: c,
            autofocus: true,
            style: mono.copyWith(fontSize: 15),
            decoration: const InputDecoration(helperText: 'For example: RE1, RE1 ST, BLD2 CLS, TR'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Redraw')),
        ],
      ),
    );
    if (code != null) widget.state.setCode(index, code);
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.state.points;
    final f = _find.trim().toUpperCase();
    final shown = [
      for (var i = 0; i < pts.length; i++)
        if (f.isEmpty || pts[i].id.toUpperCase().contains(f) || pts[i].code.toUpperCase().contains(f)) i,
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Find a point number or code',
            ),
            onChanged: (v) => setState(() => _find = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text('${shown.length} of ${pts.length} points', style: const TextStyle(color: Tone.muted, fontSize: 12)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Click: show · pencil: change code',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Tone.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemExtent: 44,
            itemBuilder: (context, k) {
              final i = shown[k];
              final p = pts[i];
              return InkWell(
                onTap: () => widget.state.showPoint(p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          p.id,
                          style: mono.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          p.code.isEmpty ? '(no code)' : p.code,
                          style: mono.copyWith(color: p.code.isEmpty ? Tone.muted : Tone.ink),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(p.z?.toStringAsFixed(3) ?? '—', style: mono.copyWith(color: Tone.muted)),
                      IconButton(
                        tooltip: 'Change the code of point ${p.id}',
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _edit(i),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ codes

class _Codes extends StatelessWidget {
  const _Codes(this.state, {required this.onSave, required this.onLoad});
  final AppState state;
  final VoidCallback onSave, onLoad;

  @override
  Widget build(BuildContext context) {
    final all = state.library.all;
    Widget group(String title, Iterable<FeatureCode> codes) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Tone.muted),
          ),
        ),
        for (final c in codes)
          ListTile(
            dense: true,
            leading: Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Tone.soft,
                border: Border.all(color: Tone.line),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(c.code, style: mono.copyWith(fontWeight: FontWeight.w700, fontSize: 12)),
            ),
            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${c.layer}${c.kind == CodeKind.point ? ' · ${symbols[c.symbol]?.label ?? 'symbol'}' : (c.lineType == 'CONTINUOUS' ? '' : ' · ${c.lineType.toLowerCase()}')}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: aciColor(c.color),
                border: Border.all(color: Tone.line),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onLoad,
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('Load a code list'),
              ),
              OutlinedButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_alt, size: 18),
                label: const Text('Save this list'),
              ),
              TextButton(onPressed: state.resetLibrary, child: const Text('Back to the standard list')),
            ],
          ),
        ),
        const _HowCodesWork(),
        group('Lines', all.where((c) => c.kind == CodeKind.line)),
        group('Points', all.where((c) => c.kind == CodeKind.point)),
      ],
    );
  }
}

class _HowCodesWork extends StatelessWidget {
  const _HowCodesWork();

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('RE1, RE2', 'Two separate road edges: the number after a code keeps lines apart'),
      ('RE1 ST', 'Start a new road edge 1 here'),
      ('RE1 END', 'The last point of this line'),
      ('BLD1 CLS', 'Close the building back to its first corner'),
      ('BLD2 RECT', 'On the 3rd corner: the 4th is added and the shape closed'),
      ('WL1 ARC … WL1 EARC', 'A curve through the points from ARC to EARC'),
      ('WL1 GT1', 'A point on two lines at once (a wall and a gate)'),
      ('TR, MH, EPL', 'Point codes: a symbol at the point'),
    ];
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E6),
        border: Border.all(color: const Color(0xFFF1D58A)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How the codes work', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final (code, what) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 132,
                    child: Text(code, style: mono.copyWith(fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                  Expanded(child: Text(what, style: const TextStyle(fontSize: 12.5, height: 1.3))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.icon, this.title, this.text);
  final IconData icon;
  final String title, text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: Tone.ok),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Tone.muted, height: 1.4),
          ),
        ],
      ),
    ),
  );
}
