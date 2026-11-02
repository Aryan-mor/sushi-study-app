import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/login_screen_model.dart';
import 'package:fladder/sushi/sushi_account_switch.dart';
import 'package:fladder/sushi/sushi_dotenv.dart';
import 'package:fladder/sushi/sushi_login_method_chooser.dart';
import 'package:fladder/sushi/sushi_main_bot_login_panel.dart';
import 'package:fladder/sushi/sushi_pending_route.dart';
import 'package:fladder/sushi/sushi_tdlib_bridge_controller.dart';
import 'package:fladder/sushi/sushi_tdlib_connecting_experience.dart';
import 'package:fladder/sushi/sushi_tdlib_login_panel.dart';
import 'package:fladder/sushi/sushi_tdlib_qr_login_panel.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/screens/login/login_screen_credentials.dart';
import 'package:fladder/sushi/sushi_login_edit_user.dart';
import 'package:fladder/screens/login/login_user_grid.dart';
import 'package:fladder/screens/shared/animated_fade_size.dart';
import 'package:fladder/sushi/sushi_login_logo.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/navigation_scaffold/components/adaptive_fab.dart';

@RoutePage()
class SushiLoginScreen extends ConsumerStatefulWidget {
  const SushiLoginScreen({super.key});

  @override
  ConsumerState<SushiLoginScreen> createState() => _SushiLoginScreenState();
}

class _SushiLoginScreenState extends ConsumerState<SushiLoginScreen> {
  bool _bootstrapping = true;
  String? _bootstrapError;
  /// True only when [_bootstrapError] came from the TDLib bridge itself (stuck initializing,
  /// landed in a failed auth state, etc) — gates showing the explicit "log out" escape hatch,
  /// since resetting Telegram auth does nothing for unrelated bootstrap failures (missing server
  /// config, network errors, etc).
  bool _bootstrapErrorIsStuckSession = false;
  bool _editUsersMode = false;
  /// TV only: false = QR-first, true = phone panel after remote select.
  bool _tvUsePhone = false;
  /// Chooser first; telegram = phone/QR session; bot = personal-bot / main-bot.
  _LoginPath _path = _LoginPath.choose;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    setState(() {
      _bootstrapping = true;
      _bootstrapError = null;
      _bootstrapErrorIsStuckSession = false;
    });

    await SushiDotenv.ensureLoaded();
    // Sushi has no HTTP API at all (R-API-4) — it never has a media server URL to require here.
    

    try {
      await ref.read(authProvider.notifier).initModel();
    } catch (e) {
      if (mounted) {
        setState(() {
          _bootstrapping = false;
          _bootstrapError = '$e';
        });
      }
      return;
    }

    if (!mounted) return;
    sushiFlushBufferedPendingPath(ref);
    final err = ref.read(authProvider).errorMessage;
    if (err != null) {
      setState(() {
        _bootstrapping = false;
        _bootstrapError = err;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _bootstrapping = false);

    // Bring the Telegram client up in the BACKGROUND. The login chooser and the phone/bot
    // panels render immediately instead of sitting behind a 15-20s "Connecting to Telegram…"
    // takeover before the user has chosen anything. Each panel re-runs ensureConfigured()
    // itself (idempotent / single-flight) and shows its own loading + recovery UI if the
    // connection is not up yet by the time the user acts. TV's QR panel starts its own QR
    // request from initState, so nothing extra is kicked off here for that path.
    unawaited(_warmTelegramInBackground(phoneFirst: !_isTv(context)));
  }

  Future<void> _warmTelegramInBackground({required bool phoneFirst}) async {
    try {
      await SushiTdlibBridgeController.instance()
          .prepareForLoginScreen(phoneFirst: phoneFirst);
    } catch (e) {
      // Not fatal at this point — the real error is surfaced with a retry when the user
      // enters the phone/QR path (that panel re-runs ensureConfigured and renders it).
      debugPrint('[sushi-login] background Telegram warm-up failed: $e');
    }
  }

  /// Retry action for a TDLib-originated error: restarts the whole app process when available
  /// (see SushiTdlibBridgeController.restartApp's doc — a plain in-process retry can end up
  /// doing nothing for a native client stuck in a `failed` auth state), falling back to a normal
  /// in-place [_bootstrap] retry on platforms without a restart implementation.
  Future<void> _retryTdlibError() async {
    final controller = SushiTdlibBridgeController.instance();
    if (!controller.canRestartApp) {
      await _bootstrap();
      return;
    }
    try {
      await controller.restartApp();
    } catch (_) {
      if (!mounted) return;
      await _bootstrap();
    }
  }

  Future<void> _confirmForceLogoutStuckSession() async {
    final loc = context.localized;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.sushiStuckSessionLogoutTitle),
        content: Text(loc.sushiStuckSessionLogoutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.logout),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SushiTdlibBridgeController.instance().resetStuckSession();
    if (!mounted) return;
    await _bootstrap();
  }

  Future<void> _onLoginSuccess() async {
    await loggedInGoToHome(context, ref);
  }

  Widget _loginLogo({bool holdEnabled = true}) {
    return const SushiLoginLogo();
  }

  bool _isTv(BuildContext context) {
    final leanBack = ref.read(argumentsStateProvider).leanBackMode;
    return leanBack || AdaptiveLayout.viewSizeOf(context) == ViewSize.television;
  }

  void _openUserEditDialogue(AccountModel user) {
    showDialog(
      context: context,
      builder: (context) => SushiLoginEditUser(user: user),
    );
  }

  void _backToAccountGrid() {
    setState(() {
      _editUsersMode = false;
      _path = _LoginPath.choose;
    });
    ref.read(authProvider.notifier).goUserSelect();
  }

  bool _consumeSystemBack(List<AccountModel> accounts, bool showAccountGrid) {
    if (_path != _LoginPath.choose) {
      setState(() => _path = _LoginPath.choose);
      return true;
    }

    if (accounts.isEmpty) return false;

    if (!showAccountGrid) {
      _backToAccountGrid();
      return true;
    }

    return false;
  }

  void _startAddAccount() {
    setState(() {
      _editUsersMode = false;
      _path = _LoginPath.choose;
    });
    ref.read(authProvider.notifier).addNewUser();
  }

  void _chooseTelegram() => setState(() => _path = _LoginPath.telegram);

  void _chooseBot() => setState(() => _path = _LoginPath.bot);

  @override
  Widget build(BuildContext context) {
    final screen = ref.watch(authProvider.select((value) => value.screen));
    final accounts = ref.watch(authProvider.select((value) => value.accounts));
    final showAccountGrid = screen == LoginScreenType.users && accounts.isNotEmpty;
    final showBackToAccounts = !showAccountGrid && accounts.isNotEmpty;
    final interceptSystemBack =
        (accounts.isNotEmpty && !showAccountGrid) || _path != _LoginPath.choose;
    final showingChooser = !_bootstrapping &&
        _bootstrapError == null &&
        !showAccountGrid &&
        _path == _LoginPath.choose;
    // Big screens / TV on the bot path: the panel splits into two side-by-side panes
    // (logo + hint | QR + button), so it needs the wider content box.
    final wideBot = _path == _LoginPath.bot &&
        !_bootstrapping &&
        _bootstrapError == null &&
        (_isTv(context) ||
            AdaptiveLayout.viewSizeOf(context) >= ViewSize.desktop);
    final maxContentWidth = showAccountGrid
        ? 1000.0
        : showingChooser
            ? 880.0
            : wideBot
                ? 900.0
                : 420.0;

    return PopScope(
      canPop: !interceptSystemBack,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _consumeSystemBack(accounts, showAccountGrid);
      },
      child: Scaffold(
      floatingActionButton: showAccountGrid
          ? Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 16,
              children: [
                AdaptiveFab(
                  context: context,
                  key: const Key('sushi_new_user_button'),
                  heroTag: 'sushi_new_user_button',
                  child: const Icon(IconsaxPlusLinear.add_square),
                  onPressed: _startAddAccount,
                ).normal,
                AdaptiveFab(
                  context: context,
                  key: const Key('sushi_edit_user_button'),
                  heroTag: 'sushi_edit_user_button',
                  backgroundColor:
                      _editUsersMode ? Theme.of(context).colorScheme.errorContainer : null,
                  child: const Icon(IconsaxPlusLinear.edit_2),
                  onPressed: () => setState(() => _editUsersMode = !_editUsersMode),
                ).normal,
              ],
            )
          : showBackToAccounts
              ? ValueListenableBuilder<bool>(
                  valueListenable: SushiTdlibConnectingExperience.isActive,
                  builder: (context, connecting, _) => connecting
                      ? const SizedBox.shrink()
                      : FloatingActionButton(
                          tooltip: context.localized.switchUser,
                          onPressed: _backToAccountGrid,
                          child: const Icon(IconsaxPlusLinear.arrow_left_2),
                        ),
                )
              : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _bootstrapping
                    // Only covers initModel() now — Telegram is warmed in the background after
                    // this clears (see _warmTelegramInBackground), so this is a short, neutral
                    // wait with no "Connecting to Telegram…" narrative before the user has even
                    // chosen a sign-in method.
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _loginLogo(holdEnabled: false),
                          const SizedBox(height: 24),
                          const CircularProgressIndicator(),
                        ],
                      )
                    : _bootstrapError != null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _loginLogo(holdEnabled: false),
                              const SizedBox(height: 16),
                              Text(
                                _bootstrapError!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Theme.of(context).colorScheme.error),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _bootstrapErrorIsStuckSession ? _retryTdlibError : _bootstrap,
                                child: Text(context.localized.retry),
                              ),
                              if (_bootstrapErrorIsStuckSession) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _confirmForceLogoutStuckSession,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Theme.of(context).colorScheme.error,
                                  ),
                                  child: Text(context.localized.logout),
                                ),
                              ],
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // On the wide bot path the panel renders the logo itself,
                              // inside its start-side pane.
                              if (!wideBot) ...[
                                _loginLogo(),
                                const SizedBox(height: 24),
                              ],
                              AnimatedFadeSize(
                                child: showAccountGrid
                                    ? LoginUserGrid(
                                        users: accounts,
                                        editMode: _editUsersMode,
                                        onPressed: (user) => sushiTapSavedAccount(context, ref, user),
                                        onLongPress: _openUserEditDialogue,
                                      )
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          if (showBackToAccounts || _path != _LoginPath.choose)
                                            ValueListenableBuilder<bool>(
                                              valueListenable:
                                                  SushiTdlibConnectingExperience.isActive,
                                              builder: (context, connecting, _) => connecting
                                                  ? const SizedBox.shrink()
                                                  : Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                                      children: [
                                                        Align(
                                                          alignment: AlignmentDirectional.centerStart,
                                                          child: TextButton.icon(
                                                            onPressed: _path != _LoginPath.choose
                                                                ? () => setState(
                                                                    () => _path = _LoginPath.choose)
                                                                : _backToAccountGrid,
                                                            icon: const Icon(
                                                                IconsaxPlusLinear.arrow_left_2),
                                                            label: Text(
                                                              _path != _LoginPath.choose
                                                                  ? (Localizations.localeOf(context)
                                                                              .languageCode ==
                                                                          'fa'
                                                                      ? 'بازگشت'
                                                                      : 'Back')
                                                                  : context.localized.switchUser,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(height: 8),
                                                      ],
                                                    ),
                                            ),
                                          switch (_path) {
                                            _LoginPath.choose => SushiLoginMethodChooser(
                                                sideBySide: AdaptiveLayout.viewSizeOf(context) !=
                                                    ViewSize.phone,
                                                onPhone: _chooseTelegram,
                                                onBot: _chooseBot,
                                              ),
                                            _LoginPath.bot => SushiMainBotLoginPanel(
                                                onSuccess: _onLoginSuccess,
                                                wide: wideBot,
                                                logo: wideBot ? _loginLogo() : null,
                                                onBack: () =>
                                                    setState(() => _path = _LoginPath.choose),
                                              ),
                                            _LoginPath.telegram => _isTv(context)
                                                ? (_tvUsePhone
                                                    ? SushiTdlibLoginPanel(
                                                        onSuccess: _onLoginSuccess,
                                                        showQrShortcut: false,
                                                        onBackToQr: () async {
                                                          final tdlib =
                                                              SushiTdlibBridgeController
                                                                  .instance();
                                                          await tdlib.resetForPhoneLogin();
                                                          await tdlib.requestQrLogin();
                                                          if (mounted) {
                                                            setState(() => _tvUsePhone = false);
                                                          }
                                                        },
                                                      )
                                                    : SushiTdlibQrLoginPanel(
                                                        onSuccess: _onLoginSuccess,
                                                        onUsePhoneNumber: () async {
                                                          await SushiTdlibBridgeController
                                                              .instance()
                                                              .resetForPhoneLogin();
                                                          if (mounted) {
                                                            setState(() => _tvUsePhone = true);
                                                          }
                                                        },
                                                        onNeedTwoFactorPassword: () {
                                                          setState(() => _tvUsePhone = true);
                                                        },
                                                      ))
                                                : SushiTdlibLoginPanel(
                                                    onSuccess: _onLoginSuccess,
                                                  ),
                                          },
                                        ],
                                      ),
                              ),
                            ],
                          ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

enum _LoginPath { choose, telegram, bot }
