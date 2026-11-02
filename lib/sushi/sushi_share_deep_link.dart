import 'dart:developer';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/sushi/sushi_pending_route.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/util/deep_link_helper.dart';

/// Builds the [DeepLink] stack for a resolved share/details target.
DeepLink sushiDeepLinkForRoute(PageRouteInfo route) {
  final path = pageRouteInfoToPath(route);
  sushiBufferPendingPath(path);

  if (route is DetailsRoute) {
    final id = route.queryParams.getString('id', '');
    log('Sushi share deep link → details id=$id');
    return DeepLink([
      HomeRoute(children: [route]),
    ]);
  }

  return DeepLink.path(path);
}

/// After login / home is ready, navigate to a buffered share link if needed.
Future<void> sushiReconcilePendingShareNavigation(
  BuildContext context,
  WidgetRef ref, {
  bool force = false,
}) async {
  
  if (ref.read(userProvider) == null) return;
  if (!context.mounted) return;

  sushiFlushBufferedPendingPath(ref);

  final pending = ref.read(sushiPendingRouteProvider);
  if (pending == null || pending.isEmpty) return;

  final router = context.router;
  final onDetails = router.stack.any((r) => r.name == DetailsRoute.name);
  if (!force && onDetails) {
    ref.read(sushiPendingRouteProvider.notifier).state = null;
    return;
  }

  ref.read(sushiPendingRouteProvider.notifier).state = null;
  log('Sushi reconciling pending share navigation → $pending');

  await router.replaceAll([const HomeRoute()]);
  if (!context.mounted) return;
  await router.navigatePath(pending);
}

/// Safety net: some platforms deliver `/share/{id}` without host/scheme or drop nested
/// [DeepLink] stacks — reconcile once the app shell is mounted.
class SushiShareDeepLinkHost extends ConsumerStatefulWidget {
  const SushiShareDeepLinkHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SushiShareDeepLinkHost> createState() => _SushiShareDeepLinkHostState();
}

class _SushiShareDeepLinkHostState extends ConsumerState<SushiShareDeepLinkHost> {
  var _reconciled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reconcileOnce());
  }

  Future<void> _reconcileOnce() async {
    if (_reconciled || !mounted) return;
    _reconciled = true;
    await sushiReconcilePendingShareNavigation(context, ref);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
