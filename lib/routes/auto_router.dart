import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/sushi/sushi_navigation.dart';
import 'package:fladder/sushi/sushi_pending_route.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/login/lock_screen.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';

const settingsPageRoute = "settings";
const controlPanelPageRoute = "control-panel";

const fullScreenRoutes = {
  PhotoViewerRoute.name,
};

const topBarNoBlurRoutes = {
  SettingsRoute.name,
  ControlPanelRoute.name,
  DetailsRoute.name,
  SearchRoute.name,
};

@AutoRouterConfig(replaceInRouteName: 'Screen|Page,Route')
class AutoRouter extends RootStackRouter {
  AutoRouter({
    required this.ref,
  });

  final WidgetRef ref;

  @override
  List<AutoRouteGuard> get guards => [...super.guards, AuthGuard(ref: ref)];

  @override
  RouteType get defaultRouteType => const RouteType.adaptive();

  @override
  List<AutoRoute> get routes => [
        ..._defaultRoutes,
        ...otherRoutes,
      ];

  final List<AutoRoute> otherRoutes = [
    _homeRoute.copyWith(
      children: [
        ...homeRoutes,
        ...detailsRoutes,
        AutoRoute(
          page: SettingsRoute.page,
          path: settingsPageRoute,
          children: _settingsChildren,
        ),
        // Personal videos (ADR 0037): side menu only, so not a home tab.
        AutoRoute(page: SushiMyVideosRoute.page, path: 'my-videos'),
      ],
    ),
    AutoRoute(page: LockRoute.page, path: '/locked'),
  ];
}

final AutoRoute _homeRoute = AutoRoute(page: HomeRoute.page, path: '/');

/// Home tabs. Sushi: dashboard / favourites / watch-later / synced (settings via its own route).
final List<AutoRoute> homeRoutes = [
  AutoRoute(
    page: DashboardRoute.page,
    initial: true,
    path: 'dashboard',
  ),
  AutoRoute(
    page: FavouritesRoute.page,
    path: 'favourites',
  ),
  AutoRoute(
    page: WatchLaterRoute.page,
    path: 'watch-later',
  ),
  AutoRoute(
    page: SyncedRoute.page,
    path: 'synced',
  ),
];

final List<AutoRoute> detailsRoutes = [
  AutoRoute(page: DetailsRoute.page, path: 'details'),
  AutoRoute(page: SearchRoute.page, path: 'search'),
  AutoRoute(page: LibrarySearchRoute.page, path: 'library'),
];

final List<AutoRoute> _defaultRoutes = [
  AutoRoute(page: SplashRoute.page, path: '/splash'),
  AutoRoute(page: LoginRoute.page, path: '/login', maintainState: false),
  AutoRoute(page: SushiLoginRoute.page, path: '/sushi-login', maintainState: false),
  AutoRoute(page: SushiLanguageRoute.page, path: '/sushi-language', maintainState: false),
  AutoRoute(page: SushiTasteWizardRoute.page, path: '/sushi-taste', maintainState: false),
];

final List<AutoRoute> _settingsChildren = [
  AutoRoute(page: SettingsSelectionRoute.page, path: 'list'),
  AutoRoute(page: ClientSettingsRoute.page, path: 'client', maintainState: false),
  AutoRoute(page: ProfileSettingsRoute.page, path: 'security', maintainState: false),
  AutoRoute(page: PlayerSettingsRoute.page, path: 'player', maintainState: false),
  AutoRoute(page: AboutSettingsRoute.page, path: 'about'),
  AutoRoute(page: SushiPlaybackDiagRoute.page, path: 'playback-diag'),
];

class LockScreenGuard extends AutoRouteGuard {
  final WidgetRef ref;

  const LockScreenGuard({required this.ref});

  @override
  Future<void> onNavigation(NavigationResolver resolver, StackRouter router) async {
    if (ref.read(lockScreenActiveProvider) && resolver.routeName != const LockRoute().routeName) {
      router.replace(const LockRoute());
      return;
    } else {
      return resolver.next(true);
    }
  }
}

class AuthGuard extends AutoRouteGuard {
  final WidgetRef ref;

  const AuthGuard({required this.ref});

  @override
  Future<void> onNavigation(NavigationResolver resolver, StackRouter router) async {
    if (resolver.route == router.current.route) {
      return;
    }

    if (ref.read(userProvider) != null ||
        resolver.routeName == LoginRoute().routeName ||
        resolver.routeName == const SushiLoginRoute().routeName ||
        resolver.routeName == SplashRoute().routeName ||
        resolver.routeName == SushiLanguageRoute().routeName ||
        resolver.routeName == SushiTasteWizardRoute().routeName) {
      // We assume the last main focus is no longer active after navigating
      lastMainFocus = null;
      return resolver.next(true);
    }

    resolver.redirectUntil<bool>(SplashRoute(loggedIn: (value) {
      final needsLanguage = ref.read(clientSettingsProvider).selectedLocale == null;
      if (value) {
        if (needsLanguage) {
          // Cold start often hits AuthGuard→Splash(callback), not bare Splash — language
          // must still run before home when the user never picked an app locale.
          sushiFlushBufferedPendingPath(ref);
          router.replaceAll([SushiLanguageRoute(thenLoggedIn: true)]);
          return;
        }
        // Same path: do not resolver.next into home — that skipped the taste wizard.
        sushiFlushBufferedPendingPath(ref);
        final ctx = router.navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          unawaited(sushiNavigateAfterLogin(ctx, ref));
          return;
        }
        resolver.next(true);
      } else {
        sushiFlushBufferedPendingPath(ref);
        router.replaceAll(sushiSignOutRouteList(ref));
        ref.read(authProvider.notifier).initModel();
      }
    }));

    // We assume the last main focus is no longer active after navigating
    lastMainFocus = null;
    return;
  }
}
