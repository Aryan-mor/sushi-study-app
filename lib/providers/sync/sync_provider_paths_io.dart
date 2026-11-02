import 'package:path_provider/path_provider.dart';

/// Native/desktop/mobile: paths used by [SyncNotifier.cleanupTemporaryFiles] / [getTempFiles].
Future<List<String>> supportAndTempPathsForCleanup() async {
  final t = await getTemporaryDirectory();
  final s = await getApplicationSupportDirectory();
  return [t.path, s.path];
}
