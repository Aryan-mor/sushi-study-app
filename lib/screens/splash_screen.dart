import 'dart:async';

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/sushi/sushi_pending_route.dart';
import 'package:fladder/sushi/sushi_session.dart';
import 'package:fladder/sushi/sushi_splash_auth.dart';
import 'package:fladder/sushi/sushi_splash_telemetry.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/sushi/sushi_splash_brand.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/sushi/sushi_local_account.dart';

@RoutePage()
class SplashScreen extends ConsumerStatefulWidget {
  final Function(bool loggedIn)? loggedIn;
  const SplashScreen({this.loggedIn, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  final _splashTiming = SushiSplashTiming();

  @override
  void initState() {
    super.initState();
    _splashTiming.markStarted();
    WidgetsBinding.instance.addPostFrameCallback((value) async {
      _splashTiming.markFirstFrame();
      if (mounted) {
        await precacheImage(
          ResizeImage.resizeIfNeeded(
            SushiSplashBrand.displaySize.round(),
            SushiSplashBrand.displaySize.round(),
            const AssetImage(SushiSplashBrand.assetPath),
          ),
          context,
        );
      }
      await Future.delayed(const Duration(milliseconds: 500));
      if (!context.mounted) return;

      _splashTiming.markAfterInitialDelay();

      final AccountModel? lastUsedAccount = ref.read(sharedUtilityProvider).getMostRecentAccount();
      final accountForSession = lastUsedAccount != null && sushiIsLocalAccount(lastUsedAccount)
          ? sushiWithDownloadPolicy(lastUsedAccount)
          : lastUsedAccount;
      ref.read(userProvider.notifier).updateUser(accountForSession);

      if (!context.mounted) return;

      final newWindow = ref.read(argumentsStateProvider).newWindow == true;
      _splashTiming.markAccountContext(
        hadAccount: lastUsedAccount != null,
        newWindow: newWindow,
        authMethod: _splashAuthMethodLabel(lastUsedAccount?.authMethod),
      );

      if (lastUsedAccount == null || newWindow) {
        callBackOrNavigate(false);
        return;
      }

      
        _splashTiming.markSessionRestoreStarted();
        late final SushiSplashAuthResult result;
        try {
          result = await sushiResolveSplashAuth(ref, lastUsedAccount)
              .timeout(const Duration(seconds: 40));
        } catch (_) {
          result = SushiSplashAuthResult.needsLogin;
          try {
            await sushiLogoutLocallySkippingServer(ref.read, fallbackAccount: lastUsedAccount);
          } catch (_) {}
        }
        _splashTiming.markSessionRestoreEnded(result != SushiSplashAuthResult.needsLogin);
        if (!context.mounted) return;
        switch (result) {
          case SushiSplashAuthResult.needsLogin:
            callBackOrNavigate(false);
          case SushiSplashAuthResult.sessionReady:
            callBackOrNavigate(true);
          case SushiSplashAuthResult.sessionWithLock:
            navigateWithLockOnLaunch();
        }
        return;
    });
  }

  static String? _splashAuthMethodLabel(Authentication? method) {
    return switch (method) {
      Authentication.autoLogin => 'autoLogin',
      Authentication.biometrics => 'biometrics',
      Authentication.passcode => 'passcode',
      Authentication.none => 'none',
      null => null,
    };
  }

  void callBackOrNavigate(bool loggedIn) {
    final needsLanguage = ref.read(clientSettingsProvider).selectedLocale == null;
    final destination = widget.loggedIn != null
        ? 'auth_guard_callback'
        : (needsLanguage ? 'language' : (loggedIn ? 'dashboard' : 'login'));
    unawaited(_splashTiming.finishAndReport(destination: destination, loggedIn: loggedIn));

    if (widget.loggedIn == null) {
      if (needsLanguage) {
        context.router.replace(SushiLanguageRoute(thenLoggedIn: loggedIn));
        return;
      }
      if (loggedIn) {
        sushiFlushBufferedPendingPath(ref);
        unawaited(sushiNavigateAfterLogin(context, ref));
      } else {
        sushiFlushBufferedPendingPath(ref);
        context.router.replace(const SushiLoginRoute());
        ref.read(authProvider.notifier).initModel();
      }
    } else {
      // AuthGuard [redirectUntil] completes via this callback only.
      // Language gate is the cold-start splash path (widget.loggedIn == null).
      widget.loggedIn?.call(loggedIn);
    }
  }

  void navigateWithLockOnLaunch() {
    final destination = widget.loggedIn != null ? 'auth_guard_callback_with_lock' : 'dashboard_with_lock';
    unawaited(_splashTiming.finishAndReport(destination: destination, loggedIn: true));

    void pushLock() {
      if (!context.mounted) return;
      context.router.push(const LockRoute());
    }

    if (widget.loggedIn == null) {
      
        sushiFlushBufferedPendingPath(ref);
        unawaited(sushiNavigateAfterLogin(context, ref));
        WidgetsBinding.instance.addPostFrameCallback((_) => pushLock());
      
    } else {
      widget.loggedIn?.call(true);
      WidgetsBinding.instance.addPostFrameCallback((_) => pushLock());
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationManagerInitializer(
      child: Scaffold(
        backgroundColor: SushiSplashBrand.splashBackground,
        body: Center(
          child: const SushiSplashBrand(),
        ),
      ),
    );
  }
}
