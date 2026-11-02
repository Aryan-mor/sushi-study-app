import 'package:flutter/foundation.dart';

/// Playback failure reporting surface (no-op; Sentry/Crashlytics removed).
abstract final class SushiPlaybackTelemetry {
  static Future<void> reportFailure({
    required String stage,
    required String reason,
    String? itemId,
    String? streamUrl,
    int? httpStatus,
    bool transient = false,
    Map<String, Object?> extra = const {},
  }) async {}

  /// Reports an uncaught exception from playback model preparation (as opposed to [reportFailure],
  /// which is for a known/named failure with no Dart exception object of its own).
  static Future<void> reportException({
    required String stage,
    required Object exception,
    StackTrace? stackTrace,
    String? itemId,
  }) async {}

  static Future<void> reportHttpFailure({
    required String method,
    required String path,
    int? statusCode,
    String? reason,
    Object? exception,
    StackTrace? stackTrace,
    int? elapsedMs,
    bool transient = false,
  }) async {}

  static Future<void> reportStuckPlayback({
    required String itemId,
    String? streamUrl,
    Duration position = Duration.zero,
    Duration? catalogDuration,
    bool nativePlayer = false,
    String stuckKind = 'start',
    bool transient = true,
  }) async {
    await reportFailure(
      stage: 'player_stuck',
      reason: stuckKind == 'mid_stream' ? 'mid_stream_frozen' : 'zero_progress_after_open',
      itemId: itemId,
      streamUrl: streamUrl,
      transient: transient,
      extra: {
        'position_ms': position.inMilliseconds,
        if (catalogDuration != null) 'catalog_duration_ms': catalogDuration.inMilliseconds,
        'native_player': nativePlayer,
        'stuck_kind': stuckKind,
      },
    );
  }

  static Future<void> reportNativePlayerError({
    required int errorCode,
    required String errorCodeName,
    String? message,
    String? itemId,
  }) async {
    final summary = message == null || message.isEmpty ? errorCodeName : '$errorCodeName: $message';
    await reportFailure(
      stage: 'exo',
      reason: summary,
      itemId: itemId,
      transient: false,
      extra: {
        'error_code': errorCode,
        'error_code_name': errorCodeName,
        if (message != null && message.isNotEmpty) 'message': message,
      },
    );
  }

  static Future<void> reportNativeOpenFailed({
    required String url,
    required int attempt,
    String? itemId,
  }) async {
    await reportFailure(
      stage: 'native_open',
      reason: 'exo_not_ready',
      itemId: itemId,
      streamUrl: url,
      transient: attempt < 4,
      extra: {'attempt': attempt},
    );
  }

  static DateTime? _lastVolumeAnomalyAt;
  static String? _lastVolumeAnomalyReason;

  /// Detects MPV play/pause fade leaving audio muted (intermittent on Android).
  static Future<void> reportVolumeAnomaly({
    required String reason,
    required double playerVolume,
    required double preferredVolume,
    bool enablePlayPauseFade = false,
    bool fadeAborted = false,
  }) async {
    final now = DateTime.now();
    if (_lastVolumeAnomalyReason == reason &&
        _lastVolumeAnomalyAt != null &&
        now.difference(_lastVolumeAnomalyAt!) < const Duration(minutes: 5)) {
      return;
    }
    _lastVolumeAnomalyAt = now;
    _lastVolumeAnomalyReason = reason;
  }

  /// Test-only reset for dedupe window.
  @visibleForTesting
  static void resetVolumeAnomalyDedupeForTest() {
    _lastVolumeAnomalyAt = null;
    _lastVolumeAnomalyReason = null;
  }
}
