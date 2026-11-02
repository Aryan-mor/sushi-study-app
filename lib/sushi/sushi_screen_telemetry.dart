import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:fladder/sushi/sushi_memory_telemetry.dart';

/// Reports screens whose first frame after navigation exceeds this threshold.
const kSushiSlowScreenFirstFrameMs = 2500;

/// Reports async screen loads (e.g. detail fetch) exceeding this threshold.
const kSushiSlowScreenLoadMs = 3000;

/// Screen load timing helpers (capture no-op; Sentry removed).
abstract final class SushiScreenTelemetry {
  static Future<T> trackLoad<T>({
    required String screen,
    String phase = 'load',
    required Future<T> Function() load,
  }) async {
    final sw = Stopwatch()..start();
    try {
      return await load();
    } finally {
      sw.stop();
      await reportIfSlow(
        screen: screen,
        phase: phase,
        ms: sw.elapsedMilliseconds,
        thresholdMs: kSushiSlowScreenLoadMs,
      );
    }
  }

  static Future<void> reportIfSlow({
    required String screen,
    required String phase,
    required int ms,
    required int thresholdMs,
  }) async {
    if (ms < thresholdMs) return;
  }
}

/// Measures time from route push to first frame (navigation + initial paint).
final class SushiRouteTelemetryObserver extends NavigatorObserver {
  final Map<Route<dynamic>, Stopwatch> _pending = {};
  String? _lastRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _routeName(route);
    final from = previousRoute != null ? _routeName(previousRoute) : _lastRoute;
    _lastRoute = name;

    final sw = Stopwatch()..start();
    _pending[route] = sw;

    SchedulerBinding.instance.scheduleFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final active = _pending.remove(route);
        if (active == null || !active.isRunning) return;
        active.stop();
        SushiScreenTelemetry.reportIfSlow(
          screen: name,
          phase: 'first_frame',
          ms: active.elapsedMilliseconds,
          thresholdMs: kSushiSlowScreenFirstFrameMs,
        );
        SushiMemoryTelemetry.onNavigation(
          action: 'push',
          route: name,
          from: from,
        );
      });
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pending.remove(route)?.stop();
    final name = _routeName(route);
    final to = previousRoute != null ? _routeName(previousRoute) : null;
    SushiMemoryTelemetry.onNavigation(
      action: 'pop',
      route: to ?? name,
      from: name,
    );
    if (previousRoute != null) {
      _lastRoute = _routeName(previousRoute);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pending.remove(route)?.stop();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      _pending.remove(oldRoute)?.stop();
    }
    if (newRoute != null) {
      didPush(newRoute, oldRoute);
    }
  }

  static String _routeName(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) return name;
    return route.runtimeType.toString();
  }
}
