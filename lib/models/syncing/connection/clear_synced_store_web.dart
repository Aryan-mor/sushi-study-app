import 'package:drift/drift.dart';

/// Web: drop rows only (Drift WASM / IndexedDB); no filesystem path.
Future<void> clearSyncedStoreRows(GeneratedDatabase db, String sqliteBaseName) async {
  await db.customStatement('DELETE FROM database_items;');
}
