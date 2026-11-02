import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Audio / volume / track-selection tracing for Android playback debug.
///
/// Visible in `pnpm dev:android:logs --stream` (filter includes `SUSHI_AUDIO`).
abstract final class SushiAudioLog {
  static const _logName = 'SUSHI_AUDIO';

  static void event(String phase, {Map<String, Object?> fields = const {}}) {
    
    final parts = <String>['phase=$phase'];
    for (final e in fields.entries) {
      final v = e.value;
      if (v == null) continue;
      parts.add('${e.key}=$v');
    }
    final line = 'SUSHI_AUDIO ${parts.join(' ')}';
    developer.log(line, name: _logName);
    debugPrint(line);
  }
}
