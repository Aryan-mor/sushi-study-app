import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// VM / mobile / desktop: native sqlite file under application support.
QueryExecutor openConnection() {
  return driftDatabase(
    name: 'syncedDatabase',
    native: DriftNativeOptions(
      databaseDirectory: () => getApplicationSupportDirectory(),
    ),
  );
}
