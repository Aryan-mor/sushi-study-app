import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import 'package:fladder/routes/auto_router.gr.dart';

/// Default search: Sushi dedicated /search UI.
PageRouteInfo sushiDefaultSearchRoute() => const SearchRoute();

void sushiNavigateToSearch(BuildContext context) {
  context.router.push(const SearchRoute());
}
