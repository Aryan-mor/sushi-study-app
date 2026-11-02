import 'package:drift/drift.dart';

/// Fallback when neither `dart.library.js_interop` (browser) nor `dart.library.io` applies.
QueryExecutor openConnection() {
  throw UnsupportedError(
    'Synced AppDatabase: unsupported platform (no dart:html / dart:io).',
  );
}
