import 'package:auto_route/auto_route.dart';

import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/routes/auto_router.gr.dart';

/// Detail-unavailable signal (capture no-op; Sentry removed).
abstract final class SushiDetailUnavailableTelemetry {
  static DateTime? _lastReportAt;
  static String? _lastItemId;

  static Future<void> report({
    required String itemId,
    required bool hadInlineItem,
    required List<String> fetchTrace,
    required int fetchAttempts,
    required StackRouter router,
    int? lastHttpStatus,
  }) async {
    if (!SushiEnv.isEnabled) return;
    if (itemId.isEmpty) return;

    final now = DateTime.now();
    if (_lastItemId == itemId &&
        _lastReportAt != null &&
        now.difference(_lastReportAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastReportAt = now;
    _lastItemId = itemId;

    // Keep navigation walk so call sites still pay the same cost / side effects locally.
    _navigationContext(router);
  }

  static Map<String, Object?> _navigationContext(StackRouter router) {
    final stack = <Map<String, Object?>>[];
    for (final page in router.stack) {
      final routeData = page.routeData;
      final entry = <String, Object?>{
        'name': page.name ?? '',
        'path': routeData.path,
      };
      final query = routeData.queryParams.rawMap;
      if (query.isNotEmpty) {
        entry['query'] = Map<String, String>.from(query);
      }
      final args = routeData.args;
      if (args is DetailsRouteArgs) {
        entry['details_id'] = args.id;
        entry['details_had_item'] = args.item != null;
        if (args.item != null) {
          entry['details_item_type'] = args.item.runtimeType.toString();
        }
      }
      stack.add(entry);
    }

    final current = router.current;
    return {
      'current_route': current.name,
      'current_path': current.path,
      'stack_depth': stack.length,
      'route_stack': stack,
    };
  }
}
