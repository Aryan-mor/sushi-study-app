import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/sushi/sushi_playback_telemetry.dart';

/// Records playback-related Jellyfin/OX HTTP failures (Sentry breadcrumbs removed).
class SushiPlaybackHttpInterceptor implements Interceptor {
  SushiPlaybackHttpInterceptor(this.ref);

  final Ref ref;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    if (!SushiEnv.isEnabled) return chain.proceed(chain.request);

    final request = chain.request;
    if (!_isPlaybackRequest(request)) return chain.proceed(request);

    final started = DateTime.now();
    final path = _safePath(request.url);
    final method = request.method;

    try {
      final response = await chain.proceed(request);
      final elapsedMs = DateTime.now().difference(started).inMilliseconds;

      if (!response.isSuccessful) {
        final reason = response.error?.toString() ?? response.base.reasonPhrase ?? 'http_error';
        unawaited(SushiPlaybackTelemetry.reportHttpFailure(
          method: method,
          path: path,
          statusCode: response.statusCode,
          reason: reason,
          elapsedMs: elapsedMs,
          transient: _isTransientPlaybackHttpFailure(response.statusCode, reason),
        ));
      }

      return response;
    } catch (e, st) {
      final elapsedMs = DateTime.now().difference(started).inMilliseconds;
      unawaited(SushiPlaybackTelemetry.reportHttpFailure(
        method: method,
        path: path,
        reason: e.runtimeType.toString(),
        exception: e,
        stackTrace: st,
        elapsedMs: elapsedMs,
      ));
      rethrow;
    }
  }

  static bool _isPlaybackRequest(Request request) {
    final path = request.url.path.toLowerCase();
    if (path.contains('playbackinfo')) return true;
    if (path.contains('/videos/') && path.contains('stream')) return true;
    if (path.contains('/sessions/playing')) return true;
    if (path.contains('/stream-nodes')) return true;
    if (path.contains('/me/stream')) return true;
    return false;
  }

  static bool _isTransientPlaybackHttpFailure(int statusCode, String reason) {
    if (statusCode == 502 || statusCode == 503 || statusCode == 504) return true;
    if (statusCode == 404 && reason.toLowerCase().contains('no playable media')) return true;
    return false;
  }

  static String _safePath(Uri url) {
    final segments = url.pathSegments;
    final sanitized = segments.map((s) {
      if (RegExp(r'^[0-9a-f-]{36}$', caseSensitive: false).hasMatch(s)) return '{id}';
      if (RegExp(r'^v/\d+').hasMatch(s)) return 'v/{variant}';
      if (RegExp(r'^\d+$').hasMatch(s)) return '{num}';
      return s;
    }).join('/');
    final q = Map<String, String>.from(url.queryParameters)..remove('token')..remove('api_key');
    if (q.isEmpty) return '/$sanitized';
    return '/$sanitized?${q.keys.join(',')}';
  }
}
