// Where the app's own files (icon, sample survey, PDF fonts) are. As its own program they are at
// their plain paths; inside another program (the Survey Toolkit) Flutter keeps them under
// packages/auto_draft/, and AutoDraftView says so.
String? assetPackage;

/// The path of one of the app's files, wherever it runs
String asset(String path) => assetPackage == null ? path : 'packages/$assetPackage/$path';
