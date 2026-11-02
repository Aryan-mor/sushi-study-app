import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Web / DDC: no `path_provider`, no `dart:io` — avoids plugin tear-offs in the graph.
QueryExecutor openConnection() {
  return driftDatabase(
    name: 'syncedDatabase',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.dart.js'),
    ),
  );
}
