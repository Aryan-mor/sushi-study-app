import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Image URL / decode tracing — grep logcat for `SUSHI_IMAGE`.
abstract final class SushiImageLog {
  static const _logName = 'SUSHI_IMAGE';

  static void event(String phase, {Map<String, Object?> fields = const {}}) {
    
    final parts = <String>['phase=$phase'];
    for (final e in fields.entries) {
      final v = e.value;
      if (v == null) continue;
      parts.add('${e.key}=$v');
    }
    final line = 'SUSHI_IMAGE ${parts.join(' ')}';
    developer.log(line, name: _logName);
    debugPrint(line);
  }
}
