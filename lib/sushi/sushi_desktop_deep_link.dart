import 'dart:developer';

import 'package:fladder/sushi/sushi_pending_route.dart';
import 'package:fladder/sushi/sushi_share_deep_link.dart';
import 'package:fladder/routes/auto_router.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/util/deep_link_helper.dart';
import 'package:protocol_handler/protocol_handler.dart';

/// Windows startup args (e.g. `sushi.exe "sushi:///share/{id}"`).
List<String> _windowsStartupArgs = const [];

void sushiRememberWindowsStartupArgs(List<String> args) {
  _windowsStartupArgs = List.unmodifiable(args);
}

/// Register `sushi://` and wire cold-start + live protocol URLs to the router.
Future<SushiWindowsDeepLinkListener?> sushiSetupWindowsDeepLinks({
  required AutoRouter autoRouter,
}) async {
  

  final listener = SushiWindowsDeepLinkListener(autoRouter);
  await listener.init();

  for (final arg in _windowsStartupArgs) {
    listener.handleUrl(arg);
  }

  return listener;
}

final class SushiWindowsDeepLinkListener with ProtocolListener {
  SushiWindowsDeepLinkListener(this._router);

  final AutoRouter _router;

  Future<void> init() async {
    protocolHandler.addListener(this);
  }

  void dispose() {
    protocolHandler.removeListener(this);
  }

  @override
  void onProtocolUrlReceived(String url) {
    handleUrl(url);
  }

  void handleUrl(String url) {
    final uri = _uriFromDeepLinkArg(url);
    if (uri == null) return;

    final route = payloadToRoute(uri);
    if (route == null) return;

    sushiDeepLinkForRoute(route);
    final path = pageRouteInfoToPath(route);
    log('Sushi Windows deep link → $path');

    try {
      if (route is DetailsRoute) {
        _router.replaceAll([
          HomeRoute(children: [route]),
        ]);
      } else {
        _router.navigatePath(path);
      }
    } catch (e, st) {
      log('Windows deep link navigation failed: $e', stackTrace: st);
    }
  }
}

Uri? _uriFromDeepLinkArg(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('$kSushiDeepLinkScheme://') || trimmed.startsWith('fladder://')) {
    return Uri.tryParse(trimmed);
  }
  return null;
}
