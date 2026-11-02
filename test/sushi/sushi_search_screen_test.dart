import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/providers/search_provider.dart';
import 'package:fladder/screens/home_screen.dart';
import 'package:fladder/screens/search/search_screen.dart';
import 'package:fladder/screens/shared/outlined_text_field.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:fladder/util/poster_defaults.dart';

void main() {
  test('fetchSuggestionNames skips empty query', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final names = await container.read(searchProvider.notifier).fetchSuggestionNames('   ');
    expect(names, isEmpty);
  });

  testWidgets('TV search uses OutlinedTextField below top navigation', (tester) async {
    const topBarHeight = 55.0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AdaptiveLayout(
            data: const AdaptiveLayoutModel(
              viewSize: ViewSize.television,
              layoutMode: LayoutMode.dual,
              inputDevice: InputDevice.dPad,
              platform: TargetPlatform.android,
              isDesktop: false,
              posterDefaults: PosterDefaults(size: 350, ratio: 0.55),
              controller: <HomeTabs, ScrollController>{},
              sideBarWidth: 80,
              topBarHeight: topBarHeight,
            ),
            child: const SearchScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SliverAppBar), findsOneWidget);
    expect(find.byType(OutlinedTextField), findsOneWidget);

    final fieldTop = tester.getTopLeft(find.byType(OutlinedTextField)).dy;
    expect(
      fieldTop,
      greaterThanOrEqualTo(topBarHeight),
      reason: 'search field must sit below TV Navigation overlay',
    );
  });
}
