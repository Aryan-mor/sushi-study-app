import 'dart:convert';
import 'dart:io';

/// Reads a file the native bridge left behind and deletes it.
///
/// gomobile must not return caller-data strings (wire replies, initData, subtitle bytes).
/// Those values abort the process in the JNI write barrier. Native code writes them to a
/// temp file and returns the path; this is the only place that turns the path back into text.
Future<String> sushiReadBridgeFile(String path) async {
  if (path.isEmpty) return '';
  final file = File(path);
  try {
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  } finally {
    try {
      await file.delete();
    } catch (_) {}
  }
}
