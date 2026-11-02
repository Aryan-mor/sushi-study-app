import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/sushi/sushi_image_auth.dart';
import 'package:fladder/sushi/sushi_navigation.dart';
import 'package:fladder/sushi/sushi_session_store.dart';
import 'package:fladder/sushi/providers/sushi_catalog_item_flags.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/localization_helper.dart';

/// Set from [BaseAppWrapper] so auth prompts can navigate to login.
final sushiSessionRouterProvider = StateProvider<StackRouter?>((ref) => null);

bool _authPromptVisible = false;

/// Shows a persistent snack when the server rejects the session (401 after refresh).
/// User can tap Log out to clear credentials and return to login.
void sushiPromptReLogin(Ref ref) {
  if (_authPromptVisible) return;
  if (ref.read(userProvider) == null) return;

  final loc = ref.read(localizationContextProvider)?.localized;
  final message = loc?.sushiSessionExpiredMessage ??
      'Your session expired. Log out and sign in again.';
  final action = loc?.logout ?? 'Log out';

  _authPromptVisible = true;
  FladderSnack.show(
    message,
    permanent: true,
    actionLabel: action,
    onActionPressed: () => sushiPerformSignOut(ref),
    showCloseButton: true,
  );
}

void sushiResetAuthPrompt() {
  _authPromptVisible = false;
}

/// Clears OX session state and routes to the login screen.
Future<void> sushiPerformSignOut(Ref ref) async {
  sushiResetAuthPrompt();
  final account = ref.read(userProvider);
  final router = ref.read(sushiSessionRouterProvider);

  if (account != null) {
    await SushiSessionStore(ref.read(sharedPreferencesProvider)).clear(account);
  }
  SushiImageAuth.clear();
  ref.read(sushiCatalogItemFlagsProvider.notifier).clear();

  await ref.read(authProvider.notifier).logOutUser();

  if (router != null) {
    await router.replaceAll(sushiSignOutRouteList());
  }
  await ref.read(authProvider.notifier).initModel();
}
