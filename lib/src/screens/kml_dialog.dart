// Before saving for Google Earth: the UTM zone the coordinates are in (they carry no zone of their
// own). Remembered for next time.
import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// (zone, north) or null when cancelled
Future<(int, bool)?> showKmlDialog(BuildContext context, int zone, bool north) =>
    showDialog<(int, bool)>(context: context, builder: (_) => _KmlDialog(zone, north));

class _KmlDialog extends StatefulWidget {
  const _KmlDialog(this.zone, this.north);
  final int zone;
  final bool north;

  @override
  State<_KmlDialog> createState() => _KmlDialogState();
}

class _KmlDialogState extends State<_KmlDialog> {
  late int zone = widget.zone;
  late bool north = widget.north;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save for Google Earth'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Which UTM zone are the coordinates in? (WGS 84)', style: TextStyle(color: Tone.muted)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('kml-zone'),
                  initialValue: zone,
                  isExpanded: true,
                  menuMaxHeight: 360,
                  decoration: const InputDecoration(labelText: 'Zone'),
                  items: [for (var z = 1; z <= 60; z++) DropdownMenuItem(value: z, child: Text('$z'))],
                  onChanged: (v) => setState(() => zone = v ?? zone),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('North')),
                  ButtonSegment(value: false, label: Text('South')),
                ],
                selected: {north},
                onSelectionChanged: (v) => setState(() => north = v.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Pakistan: 42 for Karachi, Quetta and Peshawar; 43 for Lahore, Islamabad, Multan and Faisalabad; '
            '41 west of 66° E; 44 east of 78° E.',
            style: TextStyle(color: Tone.muted, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, (zone, north)), child: const Text('Save KML')),
    ],
  );
}
