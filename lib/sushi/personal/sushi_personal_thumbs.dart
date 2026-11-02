import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:path_provider/path_provider.dart';

import 'package:fladder/sushi/sushi_bridge_queue.dart';

/// Personal video thumbnails (ADR 0037 §6). The server keeps none: the card shows a placeholder
/// until the video has been played on this device, then the thumbnail of the delivered message is
/// fetched once and kept here. The cache is disposable — lose it, and the next play rebuilds it.

const _dirName = 'sushi_personal_thumbs';

/// Bumped whenever a thumbnail lands or is pruned, so open grids repaint.
final ValueNotifier<int> sushiPersonalThumbsVersion = ValueNotifier<int>(0);

final Set<int> _inFlight = {};
Directory? _dir;

Future<Directory?> _thumbDir() async {
  if (kIsWeb) return null;
  if (_dir != null) return _dir;
  try {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  } catch (e) {
    debugPrint('[sushi] personal thumbs dir: $e');
    return null;
  }
}

String _fileName(int personalId) => '$personalId.jpg';

/// The cached thumbnail for [personalId], or null when this device has none yet.
Future<File?> sushiPersonalThumbFile(int personalId) async {
  final dir = await _thumbDir();
  if (dir == null) return null;
  final file = File('${dir.path}${Platform.pathSeparator}${_fileName(personalId)}');
  return await file.exists() ? file : null;
}

/// Fetches and keeps the thumbnail of the message a personal video was just played from.
/// Best-effort and silent: a video with no thumbnail (often one sent as a file) keeps its
/// placeholder, and a failure here never touches playback.
Future<void> sushiCachePersonalThumb({
  required int personalId,
  required int messageId,
  required String locator,
}) async {
  if (personalId <= 0 || messageId <= 0 || !_inFlight.add(personalId)) return;
  try {
    if (await sushiPersonalThumbFile(personalId) != null) return;
    final dir = await _thumbDir();
    if (dir == null) return;
    final out = '${dir.path}${Platform.pathSeparator}${_fileName(personalId)}';
    await sushiFetchDocumentThumb(messageId: messageId, locator: locator, outPath: out);
    sushiPersonalThumbsVersion.value++;
  } catch (e) {
    debugPrint('[sushi] personal thumb $personalId: $e (placeholder stays)');
  } finally {
    _inFlight.remove(personalId);
  }
}

/// Deletes thumbnails of videos no longer in My videos.
Future<void> sushiPrunePersonalThumbs(Set<int> keep) async {
  final dir = await _thumbDir();
  if (dir == null) return;
  var removed = false;
  try {
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final id = int.tryParse(name.split('.').first);
      if (id == null || keep.contains(id)) continue;
      await entity.delete();
      removed = true;
    }
  } catch (e) {
    debugPrint('[sushi] personal thumbs prune: $e');
  }
  if (removed) sushiPersonalThumbsVersion.value++;
}
