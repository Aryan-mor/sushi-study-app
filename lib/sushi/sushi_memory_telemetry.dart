import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// RSS above this on phone/tablet triggers a high-memory warning (telemetry no-op).
const kSushiHighMemoryRssMbPhone = 512;

/// Leanback / Android TV devices often have less headroom.
const kSushiHighMemoryRssMbTv = 384;

/// Cap Flutter image cache on TV while native ExoPlayer activity holds process RAM.
const kSushiTvImageCacheMaxCount = 30;
const kSushiTvImageCacheMaxBytes = 16 * 1024 * 1024;

/// Interval for RSS sampling while native player activity is foreground.
const kSushiNativePlaybackMemorySampleInterval = Duration(seconds: 45);

/// Single navigation RSS jump that triggers a warning (possible leak / retained images).
const kSushiHighMemoryNavDeltaMb = 64;

/// Minimum gap between duplicate high-memory warnings for the same screen.
const kSushiHighMemoryWarningCooldownMs = 60 * 1000;

/// Point-in-time memory counters for navigation / TV OOM heuristics.
final class SushiMemorySnapshot {
  const SushiMemorySnapshot({
    required this.rssBytes,
    required this.imageCacheBytes,
    required this.imageCacheCount,
    required this.imageCacheMaxBytes,
  });

  final int? rssBytes;
  final int imageCacheBytes;
  final int imageCacheCount;
  final int imageCacheMaxBytes;

  int? get rssMb => rssBytes == null ? null : (rssBytes! / (1024 * 1024)).round();

  Map<String, Object?> toContext() => {
        if (rssBytes != null) 'rss_bytes': rssBytes,
        if (rssMb != null) 'rss_mb': rssMb,
        'image_cache_bytes': imageCacheBytes,
        'image_cache_count': imageCacheCount,
        'image_cache_max_bytes': imageCacheMaxBytes,
      };
}

/// Samples process RSS + Flutter image cache; capture methods are no-ops (SDK removed).
abstract final class SushiMemoryTelemetry {
  static bool _leanBack = false;
  static SushiMemorySnapshot? _lastSnapshot;
  static String? _lastWarningScreen;
  static DateTime? _lastWarningAt;

  /// Called from app root when [ArgumentsModel.leanBackMode] is known.
  static void syncDeviceProfile({required bool leanBack}) {
    _leanBack = leanBack;
    if (leanBack) {
      final cache = PaintingBinding.instance.imageCache;
      cache.maximumSize = kSushiTvImageCacheMaxCount;
      cache.maximumSizeBytes = kSushiTvImageCacheMaxBytes;
    }
  }

  /// Drops decoded posters/backdrops before native ExoPlayer opens on TV.
  /// MainActivity keeps the Flutter engine alive — dual heap is the main TV OOM vector.
  static void trimBeforeNativePlayback() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    if (_leanBack) {
      cache.maximumSize = kSushiTvImageCacheMaxCount;
      cache.maximumSizeBytes = kSushiTvImageCacheMaxBytes;
    }
  }

  /// Samples RSS while [VideoPlayerActivity] is open (no route nav events during playback).
  static Future<void> sampleDuringNativePlayback() async {
    final snapshot = sample();
    final rssMb = snapshot.rssMb;
    if (rssMb == null) return;

    if (!shouldWarn(
      snapshot: snapshot,
      previous: _lastSnapshot,
      leanBack: _leanBack,
      route: 'native_playback',
      lastWarningScreen: _lastWarningScreen,
      lastWarningAt: _lastWarningAt,
      now: DateTime.now(),
    )) {
      _lastSnapshot = snapshot;
      return;
    }

    _lastWarningScreen = 'native_playback';
    _lastWarningAt = DateTime.now();
    _lastSnapshot = snapshot;
  }

  static SushiMemorySnapshot sample() {
    final cache = PaintingBinding.instance.imageCache;
    return SushiMemorySnapshot(
      rssBytes: _currentRssBytes(),
      imageCacheBytes: cache.currentSizeBytes,
      imageCacheCount: cache.currentSize,
      imageCacheMaxBytes: cache.maximumSizeBytes,
    );
  }

  static Future<void> onNavigation({
    required String action,
    required String route,
    String? from,
  }) async {
    if (kIsWeb) return;

    final snapshot = sample();
    await _reportIfHigh(
      snapshot: snapshot,
      action: action,
      route: route,
      from: from,
    );
    _lastSnapshot = snapshot;
  }

  @visibleForTesting
  static int highMemoryThresholdMb({required bool leanBack}) {
    return leanBack ? kSushiHighMemoryRssMbTv : kSushiHighMemoryRssMbPhone;
  }

  @visibleForTesting
  static bool shouldWarn({
    required SushiMemorySnapshot snapshot,
    required SushiMemorySnapshot? previous,
    required bool leanBack,
    required String route,
    required String? lastWarningScreen,
    required DateTime? lastWarningAt,
    required DateTime now,
  }) {
    final rss = snapshot.rssBytes;
    if (rss == null) return false;

    final thresholdBytes = highMemoryThresholdMb(leanBack: leanBack) * 1024 * 1024;
    final overAbsolute = rss >= thresholdBytes;

    final prevRss = previous?.rssBytes;
    final deltaBytes = prevRss == null ? 0 : rss - prevRss;
    final overDelta = deltaBytes >= kSushiHighMemoryNavDeltaMb * 1024 * 1024;

    if (!overAbsolute && !overDelta) return false;

    if (lastWarningScreen == route &&
        lastWarningAt != null &&
        now.difference(lastWarningAt).inMilliseconds < kSushiHighMemoryWarningCooldownMs) {
      return false;
    }

    return true;
  }

  static int? _currentRssBytes() {
    if (kIsWeb) return null;
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _reportIfHigh({
    required SushiMemorySnapshot snapshot,
    required String action,
    required String route,
    String? from,
  }) async {
    final now = DateTime.now();
    if (!shouldWarn(
      snapshot: snapshot,
      previous: _lastSnapshot,
      leanBack: _leanBack,
      route: route,
      lastWarningScreen: _lastWarningScreen,
      lastWarningAt: _lastWarningAt,
      now: now,
    )) {
      return;
    }

    _lastWarningScreen = route;
    _lastWarningAt = now;
  }
}
