// What the Help box and Report a problem say about Auto Draft
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../assets.dart';
import '../brand.dart';
import 'help.dart';

final appInfo = AppInfo(
  name: appName,
  version: appVersion,
  publisher: appPublisher,
  program: 'auto-draft',
  guideUrl: '$websiteUrl/auto-draft',
  whatsNewUrl: '$websiteUrl/whats-new/auto-draft',
  openUrl: (url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  },
  icon: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.asset(asset('assets/brand/icon-512.png'))),
);

/// The keys Auto Draft knows
Future<void> showShortcuts(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Keyboard shortcuts'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (keys, what) in [
          ('Ctrl+O', 'Open a survey file'),
          ('Ctrl+S', 'Save the DXF'),
          ('Ctrl+Z', 'Undo'),
          ('Ctrl+Y  or  Ctrl+Shift+Z', 'Redo'),
          ('F1', 'Help'),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 190,
                  child: Text(keys, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text(what),
              ],
            ),
          ),
      ],
    ),
    actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
  ),
);
