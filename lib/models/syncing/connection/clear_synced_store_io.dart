import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Native: delete the sqlite file on disk (same layout as Drift native default).
Future<void> clearSyncedStoreRows(GeneratedDatabase _, String sqliteBaseName) async {
  final dbPath = await getApplicationSupportDirectory();
  final dbFile = File(p.join(dbPath.path, '$sqliteBaseName.sqlite'));
  if (await dbFile.exists()) {
    await dbFile.delete(recursive: true);
  }
}
