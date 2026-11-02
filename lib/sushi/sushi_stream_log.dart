import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Stream playback tracing — visible in `pnpm dev:android:logs --stream`.
///
/// Chopper only logs Jellyfin API (`api.sushi.*`). Video bytes go direct to
/// the device's own TDLib session and never hit the HTTP client interceptor.
abstract final class SushiStreamLog {
  static const _logName = 'SUSHI_STREAM';

  static void event(String phase, {Map<String, Object?> fields = const {}}) {
    
    final parts = <String>['phase=$phase'];
    for (final e in fields.entries) {
      final v = e.value;
      if (v == null) continue;
      parts.add('${e.key}=${_clipField(v)}');
    }
    final line = 'SUSHI_STREAM ${parts.join(' ')}';
    developer.log(line, name: _logName);
    debugPrint(line);
  }

  static String _clipField(Object v) {
    final s = v.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length <= 80) return s;
    return '${s.substring(0, 80)}…';
  }

  /// Redacts JWT/token query params; keeps host + path for CDN debugging.
  static String describeUrl(String? url) {
    if (url == null || url.isEmpty) return '(empty)';
    final uri = Uri.tryParse(url);
    if (uri == null) return '(invalid)';
    final redacted = Map<String, String>.from(uri.queryParameters)
      ..remove('token')
      ..remove('api_key')
      ..remove('ApiKey');
    final q = redacted.isEmpty
        ? ''
        : '?${redacted.entries.map((e) => '${e.key}=…').join('&')}';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port${uri.path}$q';
  }

  static String? describeHost(String? url) {
    if (url == null || url.isEmpty) return null;
    return Uri.tryParse(url)?.host;
  }

  static String formatDuration(Duration? d) {
    if (d == null) return 'null';
    final sec = d.inSeconds;
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m}m${s}s (${d.inMilliseconds}ms)';
  }

}
