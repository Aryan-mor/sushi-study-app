import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/sushi/cache/sushi_catalog.dart';
import 'package:fladder/sushi/cache/sushi_catalog_controller.dart';
import 'package:fladder/sushi/sushi_local_session.dart';
import 'package:fladder/sushi/sushi_play_warmup.dart';

final sushiCatalogDbProvider = Provider<SushiCatalogDatabase>((ref) {
  final db = SushiCatalogDatabase();
  ref.onDispose(db.close);
  return db;
});

final sushiCatalogControllerProvider = Provider<SushiCatalogController>((ref) {
  final catalog = SushiCatalogController(
    ref.watch(sushiCatalogDbProvider),
    sessionOwner: sushiCatalogSessionOwnerFromAssignment,
    readPersistedOwner: SushiCatalogOwnerStore.read,
    persistOwner: SushiCatalogOwnerStore.write,
  );
  final lifecycle = _SushiPrefetchLifecycle(catalog);
  WidgetsBinding.instance.addObserver(lifecycle);
  ref.onDispose(() {
    catalog.cancelPrefetch();
    WidgetsBinding.instance.removeObserver(lifecycle);
  });
  return catalog;
});

class _SushiPrefetchLifecycle with WidgetsBindingObserver {
  _SushiPrefetchLifecycle(this._catalog);

  final SushiCatalogController _catalog;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _catalog.cancelPrefetch();
        sushiPlayWarmup.pause();
      case AppLifecycleState.resumed:
        _catalog.resumePrefetch();
        sushiPlayWarmup.resume();
      case AppLifecycleState.inactive:
        break;
    }
  }
}
