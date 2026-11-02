import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:fladder/screens/library_search/library_search_screen.dart';
import 'package:fladder/sushi/sushi_views.dart';

@RoutePage()
class WatchLaterScreen extends StatelessWidget {
  const WatchLaterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LibrarySearchScreen(viewModelId: sushiViewLater);
  }
}
