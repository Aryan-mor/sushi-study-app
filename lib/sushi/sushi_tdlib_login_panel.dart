import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/sushi/sushi_brand.dart';
import 'package:fladder/sushi/sushi_dpad_text_field.dart';
import 'package:fladder/sushi/sushi_tdlib_bridge_controller.dart';
import 'package:fladder/sushi/sushi_tdlib_connecting_experience.dart';
import 'package:fladder/sushi/sushi_tdlib_qr_login_panel.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_local_account.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

/// Phone+code(+2FA) sign-in: the user's real Telegram account, authenticated entirely on-device
/// via TDLib. Once TDLib reports ready, runs Sushi `/initbot` and ensures a local account —
/// no HTTP OX session exchange.
///
/// TV (D-pad) uses [SushiDpadTextField]: visible focus ring, Select opens system IME.
///
/// TODO(l10n): strings here are hardcoded pending ARB entries; follow the sushiLogin* key
/// convention used elsewhere once these are ready to localize.
class SushiTdlibLoginPanel extends ConsumerStatefulWidget {
  const SushiTdlibLoginPanel({
    required this.onSuccess,
    this.showQrShortcut = true,
    this.onBackToQr,
    super.key,
  });

  final Future<void> Function() onSuccess;

  /// Phone/tablet: QR icon beside Continue. Off on TV when user already came from QR.
  final bool showQrShortcut;

  /// TV: return to QR-first panel (caller resets TDLib + flips UI).
  final Future<void> Function()? onBackToQr;

  @override
  ConsumerState<SushiTdlibLoginPanel> createState() => _SushiTdlibLoginPanelState();
}

class _SushiTdlibLoginPanelState extends ConsumerState<SushiTdlibLoginPanel> {
  final _controller = SushiTdlibBridgeController.instance();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _phoneFieldKey = GlobalKey<SushiDpadTextFieldState>();
  final _codeFieldKey = GlobalKey<SushiDpadTextFieldState>();
  final _passwordFieldKey = GlobalKey<SushiDpadTextFieldState>();
  final _submitFocus = FocusNode();
  final _eyeFocus = FocusNode();
  final _qrFocus = FocusNode();
  final _backToQrFocus = FocusNode();
  bool _busy = false;
  /// Sync gate — [setState] `_busy` alone races keyboard Done + Continue tap → double SMS.
  bool _submitLocked = false;
  bool _passwordVisible = false;
  /// Stay on 2FA UI if native briefly emits failed (wrong password) instead of waitingForPassword.
  bool _lockOnTwoFactor = false;
  String? _error;
  /// True when [_error] is the "wrong Telegram identity connected" message from
  /// _maybeStartSushiExchange's bot-session guard — its recovery action is a reset
  /// (resetForPhoneLogin), not a doomed retry of the same exchange.
  bool _blockedByBotSession = false;
  bool _sushiExchangeStarted = false;
  bool _qrSheetOpen = false;
  SushiTdlibAuthStateKind? _lastKind;
  /// Phone last submitted to Telegram — shown on code step + used after back.
  String? _submittedPhone;
  /// Bump when entering WaitCode so TextField remounts with a fresh input connection.
  int _codeFieldGeneration = 0;

  @override
  void initState() {
    super.initState();
    _lastKind = _controller.state.kind;
    _controller.addListener(_onStateChanged);
    _phoneController.addListener(_onPhoneTextChanged);
    // Telegram is warmed in the background from the login screen (no pre-choice "connecting"
    // takeover any more), so it may not be past setTdlibParameters yet when this panel mounts.
    // ensureConfigured() is idempotent / single-flight — it just joins that in-flight attempt.
    unawaited(_ensureConnected());
    // TDLib is warmed in SushiLoginScreen bootstrap — focus the active auth field.
    // When QR hands off mid-2FA, kind is already waitingForPassword on first mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusAuthField(_controller.state.kind, showIme: true);
      // _onStateChanged only fires on a FUTURE transition — it never ran for whatever
      // transition already landed this at `ready` before this panel existed to listen. That
      // never happened before prepareForLoginScreen stopped force-resetting an already-`ready`
      // Telegram session on mount (see its doc); now it's the normal case for a leftover valid
      // session, and without this the panel just sits on "ready" forever with no OX exchange
      // ever kicked off. Reuses _onStateChanged itself so the exchange-start guard
      // (_sushiExchangeStarted) stays the single source of truth — safe to call unconditionally.
      _onStateChanged();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChanged);
    _phoneController.removeListener(_onPhoneTextChanged);
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _phoneFocus.dispose();
    _codeFocus.dispose();
    _passwordFocus.dispose();
    _submitFocus.dispose();
    _eyeFocus.dispose();
    _qrFocus.dispose();
    _backToQrFocus.dispose();
    super.dispose();
  }

  void _onPhoneTextChanged() {
    if (mounted) setState(() {});
  }

  /// Native client is down or not past WaitTdlibParameters — phone form still shows so the
  /// user can type while [ensureConfigured] runs in the background.
  static bool _isPhoneWarmupKind(SushiTdlibAuthStateKind kind) {
    switch (kind) {
      case SushiTdlibAuthStateKind.uninitialized:
      case SushiTdlibAuthStateKind.closed:
      case SushiTdlibAuthStateKind.loggingOut:
        return true;
      default:
        return false;
    }
  }

  /// Joins the background warm-up. Phone field stays visible; errors render under the form.
  Future<void> _ensureConnected({bool throwOnError = false}) async {
    if (!mounted) return;
    if (!_isPhoneWarmupKind(_controller.state.kind) &&
        _controller.state.kind != SushiTdlibAuthStateKind.waitingForPhoneNumber) {
      return;
    }
    try {
      await _controller.ensureConfigured();
    } catch (e) {
      if (throwOnError) rethrow;
      if (mounted) setState(() => _error = sushiTdlibAuthUserMessage(e));
    }
  }

  void _onSubmitPressed() {
    if (_busy || _submitLocked) return;
    final kind = _controller.state.kind;
    final onPassword = kind == SushiTdlibAuthStateKind.waitingForPassword ||
        (_lockOnTwoFactor && kind == SushiTdlibAuthStateKind.failed);
    final canSubmit = switch (kind) {
      SushiTdlibAuthStateKind.waitingForCode => _codeController.text.trim().isNotEmpty,
      SushiTdlibAuthStateKind.waitingForPassword => _passwordController.text.isNotEmpty,
      SushiTdlibAuthStateKind.failed when onPassword => _passwordController.text.isNotEmpty,
      SushiTdlibAuthStateKind.waitingForPhoneNumber ||
      SushiTdlibAuthStateKind.uninitialized ||
      SushiTdlibAuthStateKind.closed ||
      SushiTdlibAuthStateKind.loggingOut =>
        _phoneController.text.trim().isNotEmpty,
      _ => false,
    };
    if (!canSubmit) {
      setState(() {
        _error = onPassword
            ? 'Enter your two-factor password'
            : switch (kind) {
                SushiTdlibAuthStateKind.waitingForCode => 'Enter the code from Telegram',
                _ => 'Enter a phone number with country code',
              };
      });
      return;
    }
    unawaited(_submit());
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _focusAuthField(SushiTdlibAuthStateKind kind, {required bool showIme, int retry = 0}) {
    final field = switch (kind) {
      SushiTdlibAuthStateKind.waitingForPhoneNumber ||
      SushiTdlibAuthStateKind.uninitialized ||
      SushiTdlibAuthStateKind.closed ||
      SushiTdlibAuthStateKind.loggingOut =>
        _phoneFieldKey.currentState,
      SushiTdlibAuthStateKind.waitingForCode => _codeFieldKey.currentState,
      SushiTdlibAuthStateKind.waitingForPassword => _passwordFieldKey.currentState,
      _ => null,
    };
    if (field == null) {
      final expectsField = kind == SushiTdlibAuthStateKind.waitingForPhoneNumber ||
          _isPhoneWarmupKind(kind) ||
          kind == SushiTdlibAuthStateKind.waitingForCode ||
          kind == SushiTdlibAuthStateKind.waitingForPassword;
      if (showIme && expectsField && retry < 8) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _focusAuthField(kind, showIme: showIme, retry: retry + 1);
        });
      }
      return;
    }
    // TV: ring only. Phone: EditableText + correct keyboardType (never bare TextInput.show).
    if (!showIme || AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad) {
      field.requestFocus();
      return;
    }
    field.requestFocusAndShowIme();
  }

  /// Close previous IME, then open the correct keyboard for the new auth step.
  /// Phone → code and code → 2FA must dismiss first or Android keeps the wrong pad.
  /// QR → 2FA handoff must NOT dismiss first (nothing to reset; dismiss fights IME open).
  void _syncKeyboardForAuthStep({
    required SushiTdlibAuthStateKind? from,
    required SushiTdlibAuthStateKind to,
  }) {
    if (from == to) return;
    final needsImeReset = (from == SushiTdlibAuthStateKind.waitingForPhoneNumber &&
            to == SushiTdlibAuthStateKind.waitingForCode) ||
        (from == SushiTdlibAuthStateKind.waitingForCode &&
            to == SushiTdlibAuthStateKind.waitingForPassword);
    if (needsImeReset) {
      _dismissKeyboard();
    }
    // Android needs a beat after hide before a different keyboardType can attach.
    final delayMs = needsImeReset ? 400 : 80;
    Future<void>.delayed(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      _focusAuthField(to, showIme: true);
    });
  }

  void _onStateChanged() {
    if (!mounted) return;
    final kind = _controller.state.kind;
    final prev = _lastKind;
    _lastKind = kind;
    if (kind == SushiTdlibAuthStateKind.waitingForPassword) {
      _lockOnTwoFactor = true;
    } else if (kind == SushiTdlibAuthStateKind.ready ||
        kind == SushiTdlibAuthStateKind.waitingForPhoneNumber ||
        kind == SushiTdlibAuthStateKind.waitingForCode ||
        kind == SushiTdlibAuthStateKind.waitingForQrConfirmation) {
      _lockOnTwoFactor = false;
    }
    // Drop spinner as soon as TDLib advances (WaitCode can arrive before RPC Ok returns —
    // otherwise Continue stays spinning through slow Telegram DC handshakes).
    final advancedPastSubmit = prev != kind &&
        (kind == SushiTdlibAuthStateKind.waitingForCode ||
            kind == SushiTdlibAuthStateKind.waitingForPassword ||
            kind == SushiTdlibAuthStateKind.ready);
    setState(() {
      if (advancedPastSubmit) {
        _busy = false;
        // WaitCode can arrive before submitPhoneNumber's finally — unlock so the
        // code field is enabled and can take focus + numeric IME.
        _submitLocked = false;
        if (kind == SushiTdlibAuthStateKind.waitingForCode &&
            prev == SushiTdlibAuthStateKind.waitingForPhoneNumber) {
          _codeFieldGeneration++;
          _codeController.clear();
        }
        // Late success after a timeout error — clear stale message.
        // Keep error when re-entering waitingForPassword after a wrong-password attempt.
        if (kind != SushiTdlibAuthStateKind.waitingForPassword || prev != kind) {
          _error = null;
        }
      }
    });
    if (prev != kind) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncKeyboardForAuthStep(from: prev, to: kind);
      });
    }
    if (kind == SushiTdlibAuthStateKind.ready && !_sushiExchangeStarted) {
      _dismissKeyboard();
      unawaited(_maybeStartSushiExchange());
    }
  }

  /// Guards the ready-triggered initbot against a restored *bot* session — this panel is the
  /// personal Telegram account (phone/QR) sign-in. A bot session landing here happens when this
  /// device's connected delivery bot (see /connectbot, ensureBotSessionFromCacheIfNeeded) got
  /// restored instead of — or after losing — the real user session; skip and let the phone form
  /// render normally.
  ///
  /// Uses isNativeSessionActuallyBot (native ground truth), not the Dart-cached flag — this
  /// exact scenario is native silently restoring a persisted bot session without Dart ever
  /// calling submitBotToken this run, which the cached flag gets wrong (see its own doc).
  Future<void> _maybeStartSushiExchange() async {
    if (_sushiExchangeStarted) return;
    if (await _controller.isNativeSessionActuallyBot()) {
      debugPrint('[sushi-tdlib-auth] login panel: ready state is a bot session, skipping exchange');
      // Without an error, a bot session left the screen looking "done" with no way forward.
      if (mounted) {
        setState(() {
          _error = 'This device has a different Telegram identity connected (not your account).';
          _blockedByBotSession = true;
        });
      }
      return;
    }
    if (!mounted || _controller.state.kind != SushiTdlibAuthStateKind.ready || _sushiExchangeStarted) {
      return;
    }
    _sushiExchangeStarted = true;
    await _exchangeWithSushiInitbot();
  }

  /// Sushi path: run `/initbot` after TDLib ready, then persist local account.
  Future<void> _exchangeWithSushiInitbot() async {
    setState(() => _error = null);
    try {
      final assignment = await sushiRunInitbotAfterTdlibReady();
      sushiEnsureAssignmentReady(assignment);
      await sushiEnsureLocalAccount(ref);
      await widget.onSuccess();
    } catch (e) {
      // Keep _sushiExchangeStarted so the ready UI shows the error + Try again
      // instead of the "setting up" animation looping forever.
      if (mounted) setState(() => _error = sushiTdlibAuthUserMessage(e));
    }
  }

  Future<void> _submit() async {
    if (_submitLocked || _busy) return;
    _submitLocked = true;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final kind = _controller.state.kind;
      final onPassword = kind == SushiTdlibAuthStateKind.waitingForPassword ||
          (_lockOnTwoFactor && kind == SushiTdlibAuthStateKind.failed);
      if (onPassword) {
        if (_passwordController.text.isEmpty) {
          throw SushiTdlibBridgeException('Enter your two-factor password');
        }
        _dismissKeyboard();
        await _controller.submitTwoFactorPassword(_passwordController.text);
      } else {
        switch (kind) {
          case SushiTdlibAuthStateKind.waitingForCode:
            final code = _codeController.text.trim();
            if (code.isEmpty) {
              throw SushiTdlibBridgeException('Enter the code from Telegram');
            }
            // Dismiss numeric pad immediately — next step may be text 2FA password.
            _dismissKeyboard();
            await _controller.submitCode(code);
            break;
          case SushiTdlibAuthStateKind.waitingForQrConfirmation:
            setState(() => _error = 'Finish QR sign-in, or cancel it first.');
            break;
          case SushiTdlibAuthStateKind.waitingForPhoneNumber:
          case SushiTdlibAuthStateKind.uninitialized:
          case SushiTdlibAuthStateKind.closed:
          case SushiTdlibAuthStateKind.loggingOut:
            await _submitEnteredPhone();
            break;
          default:
            throw SushiTdlibBridgeException(
              'Unexpected login state (${kind.name}). Use Retry on the login screen.',
            );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = sushiTdlibAuthUserMessage(e));
    } finally {
      _submitLocked = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitEnteredPhone() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      throw SushiTdlibBridgeException('Enter a phone number with country code');
    }
    if (_isPhoneWarmupKind(_controller.state.kind)) {
      await _ensureConnected(throwOnError: true);
    }
    if (_controller.state.kind != SushiTdlibAuthStateKind.waitingForPhoneNumber) {
      throw SushiTdlibBridgeException(
        'Telegram is not ready for phone login yet (state=${_controller.state.kind.name})',
      );
    }
    // Dismiss before RPC — Android keeps IME open if focus moves later without hide.
    _dismissKeyboard();
    _submittedPhone = phone;
    await _controller.submitPhoneNumber(phone);
  }

  Future<void> _backToPhoneNumber() async {
    if (_busy || _submitLocked) return;
    _dismissKeyboard();
    setState(() {
      _busy = true;
      _error = null;
      _codeController.clear();
      _passwordController.clear();
      _lockOnTwoFactor = false;
    });
    try {
      await _controller.resetForPhoneLogin();
      if (!mounted) return;
      // Prefer previously typed number so user can edit instead of retyping.
      if (_submittedPhone != null && _submittedPhone!.isNotEmpty) {
        _phoneController.text = _submittedPhone!;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusAuthField(SushiTdlibAuthStateKind.waitingForPhoneNumber, showIme: true);
      });
    } catch (e) {
      if (mounted) setState(() => _error = sushiTdlibAuthUserMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelQrAndReturnToPhone() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _controller.resetForPhoneLogin();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _focusAuthField(SushiTdlibAuthStateKind.waitingForPhoneNumber, showIme: true);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = sushiTdlibAuthUserMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openQrSheet() async {
    if (_qrSheetOpen || _busy || _submitLocked) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _controller.ensureConfigured();
      final kind = _controller.state.kind;
      if (kind != SushiTdlibAuthStateKind.waitingForPhoneNumber &&
          kind != SushiTdlibAuthStateKind.uninitialized &&
          kind != SushiTdlibAuthStateKind.waitingForQrConfirmation) {
        await _controller.resetForPhoneLogin();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = sushiTdlibAuthUserMessage(e);
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    _qrSheetOpen = true;
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!rootContext.mounted) {
        _qrSheetOpen = false;
        return;
      }
      showModalBottomSheet<void>(
        context: rootContext,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          final bottom = MediaQuery.paddingOf(sheetContext).bottom;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + bottom),
              child: SushiTdlibQrLoginPanel(
                onSuccess: () async {
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  await widget.onSuccess();
                },
                onNeedTwoFactorPassword: () {
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
            ),
          );
        },
      ).whenComplete(() async {
        _qrSheetOpen = false;
        if (!mounted) return;
        final kind = _controller.state.kind;
        // Only skip reset when already back on a phone-auth step (or signed in).
        if (kind == SushiTdlibAuthStateKind.ready ||
            kind == SushiTdlibAuthStateKind.waitingForPhoneNumber ||
            kind == SushiTdlibAuthStateKind.waitingForCode ||
            kind == SushiTdlibAuthStateKind.waitingForPassword) {
          if (mounted) {
            setState(() {});
            if (kind == SushiTdlibAuthStateKind.waitingForPassword) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _syncKeyboardForAuthStep(
                  from: SushiTdlibAuthStateKind.waitingForQrConfirmation,
                  to: SushiTdlibAuthStateKind.waitingForPassword,
                );
              });
            }
          }
          return;
        }
        await _cancelQrAndReturnToPhone();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = _controller.state.kind;

    // Show QR icon whenever the phone-number Continue row is visible — not only for
    // waitingForPhoneNumber (after QR abort/reset kind can briefly be closed/failed/uninitialized).
    final showPasswordStep = kind == SushiTdlibAuthStateKind.waitingForPassword ||
        (_lockOnTwoFactor && kind == SushiTdlibAuthStateKind.failed);
    final onPhoneContinueStep = switch (kind) {
      SushiTdlibAuthStateKind.waitingForCode ||
      SushiTdlibAuthStateKind.waitingForPassword ||
      SushiTdlibAuthStateKind.ready =>
        false,
      SushiTdlibAuthStateKind.failed when _lockOnTwoFactor => false,
      SushiTdlibAuthStateKind.waitingForQrConfirmation => _qrSheetOpen,
      _ => true,
    };
    final showQrOption = widget.showQrShortcut && onPhoneContinueStep;
    final showBackToQr = widget.onBackToQr != null && onPhoneContinueStep;
    final showBackToPhone = showPasswordStep || kind == SushiTdlibAuthStateKind.waitingForCode;
    final warmingTelegram = _isPhoneWarmupKind(kind) && _error == null;

    if (kind == SushiTdlibAuthStateKind.waitingForQrConfirmation && !_qrSheetOpen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('QR sign-in in progress', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Open the QR sheet to scan, or cancel to enter a phone number.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton(
            focusNode: _submitFocus,
            autofocus: true,
            style: FilledButton.styleFrom(
              shape: FladderTheme.largeShape,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _busy ? null : _openQrSheet,
            child: const Text('Show QR code'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            focusNode: _backToQrFocus,
            style: OutlinedButton.styleFrom(
              shape: FladderTheme.largeShape,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _busy ? null : _cancelQrAndReturnToPhone,
            child: const Text('Use phone number instead'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      );
    }

    late final Widget field;
    late final String buttonLabel;
    final effectiveKind =
        showPasswordStep ? SushiTdlibAuthStateKind.waitingForPassword : kind;
    switch (effectiveKind) {
      case SushiTdlibAuthStateKind.waitingForCode:
        final phoneLabel = (_submittedPhone?.trim().isNotEmpty ?? false)
            ? _submittedPhone!.trim()
            : (_phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : 'your number');
        field = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A login code was sent to $phoneLabel in Telegram. Enter the code from your Telegram account.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            KeyedSubtree(
              key: ValueKey('tdlib-auth-code-$_codeFieldGeneration'),
              child: SushiDpadTextField(
                key: _codeFieldKey,
                controller: _codeController,
                focusNode: _codeFocus,
                label: 'Code',
                hint: '• • • • •',
                // Phone dialpad on Android/Gboard (TextInputType.number often opens QWERTY+row).
                // digitsOnly still strips non-digits.
                keyboardType: TextInputType.phone,
                textAlign: TextAlign.center,
                autofocus: false,
                enabled: !_busy && !_submitLocked,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
                onChanged: (value) {
                  setState(() {});
                  // Telegram login codes are 5 digits — submit as soon as it's complete.
                  if (value.trim().length == 5 && !_submitLocked && !_busy) {
                    _dismissKeyboard();
                    unawaited(_submit());
                  }
                },
                onKeyboardClosed: () {
                  if (_codeController.text.trim().isNotEmpty && !_submitLocked && !_busy) {
                    _dismissKeyboard();
                    unawaited(_submit());
                  }
                },
                onMoveFocusDown: () => _submitFocus.requestFocus(),
              ),
            ),
          ],
        );
        buttonLabel = 'Confirm code';
        break;
      case SushiTdlibAuthStateKind.waitingForPassword:
        final hint = _controller.state.passwordHint;
        final fieldsEnabled = !_busy && !_submitLocked;
        field = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SushiDpadTextField(
                key: _passwordFieldKey,
                controller: _passwordController,
                focusNode: _passwordFocus,
                label: 'Two-factor password',
                hint: (hint != null && hint.isNotEmpty) ? hint : null,
                obscureText: !_passwordVisible,
                keyboardType: TextInputType.visiblePassword,
                autofocus: false,
                enabled: fieldsEnabled,
                onChanged: (_) => setState(() {}),
                onKeyboardClosed: () {
                  if (_passwordController.text.isNotEmpty && !_submitLocked && !_busy) {
                    _submitFocus.requestFocus();
                  }
                },
                onMoveFocusDown: () => _eyeFocus.requestFocus(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 52,
              height: 52,
              child: IconButton.outlined(
                focusNode: _eyeFocus,
                tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                style: IconButton.styleFrom(shape: FladderTheme.largeShape).copyWith(
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.focused)) {
                      return BorderSide(color: theme.colorScheme.primary, width: 3);
                    }
                    return BorderSide(color: theme.colorScheme.outline);
                  }),
                ),
                onPressed: fieldsEnabled
                    ? () => setState(() => _passwordVisible = !_passwordVisible)
                    : null,
                icon: Icon(
                  _passwordVisible ? IconsaxPlusLinear.eye_slash : IconsaxPlusLinear.eye,
                ),
              ),
            ),
          ],
        );
        buttonLabel = 'Confirm password';
        break;
      case SushiTdlibAuthStateKind.ready:
        // Authenticated — now running the OX/initbot exchange + local account setup
        // before Home. A real multi-second wait the user opted into, so use the
        // typewriter "setting up" experience rather than a checkmark + bare spinner.
        // On error, fall back to an actionable retry.
        if (_error == null) {
          return const SushiTdlibConnectingExperience();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(IconsaxPlusBold.warning_2, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  if (_blockedByBotSession) {
                    setState(() {
                      _error = null;
                      _blockedByBotSession = false;
                    });
                    unawaited(_controller.resetForPhoneLogin());
                    return;
                  }
                  _sushiExchangeStarted = true;
                  unawaited(_exchangeWithSushiInitbot());
                },
                child: Text(_blockedByBotSession ? 'Log out and use phone number' : 'Try again'),
              ),
            ],
          ),
        );
      default:
        field = SushiDpadTextField(
          key: _phoneFieldKey,
          controller: _phoneController,
          focusNode: _phoneFocus,
          label: 'Phone number',
          hint: '+1 234 567 8900',
          keyboardType: TextInputType.phone,
          autofocus: true,
          enabled: !_busy && !_submitLocked,
          autofillHints: const [AutofillHints.telephoneNumber],
          onChanged: (_) => setState(() {}),
          onKeyboardClosed: () {
            // Enter/Done: dismiss IME + submit so WaitCode can autofocus code field.
            if (_phoneController.text.trim().isNotEmpty && !_submitLocked && !_busy) {
              unawaited(_submit());
            }
          },
          onMoveFocusDown: () => _submitFocus.requestFocus(),
        );
        buttonLabel = 'Continue';
    }

    final sendingPhone = _busy &&
        (kind == SushiTdlibAuthStateKind.waitingForPhoneNumber || _isPhoneWarmupKind(kind));
    // Keep buttons focusable for D-pad even when the field is empty — null onPressed
    // removes the node from the focus tree and traps the remote on the TextField.
    final actionsEnabled = !_busy && !_submitLocked;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sign in with Telegram',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Log into your Telegram account to use ${SushiBrand.appName}.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FocusTraversalOrder(
            order: const NumericFocusOrder(1),
            child: field,
          ),
          if (warmingTelegram && !sendingPhone) ...[
            const SizedBox(height: 12),
            Text(
              'Preparing Telegram… you can enter your number now.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (sendingPhone) ...[
            const SizedBox(height: 12),
            Text(
              'Contacting Telegram…',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: FilledButton(
                    focusNode: _submitFocus,
                    style: FilledButton.styleFrom(
                      shape: FladderTheme.largeShape,
                      minimumSize: const Size.fromHeight(52),
                    ).copyWith(
                      side: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.focused)) {
                          return BorderSide(
                            color: theme.colorScheme.secondary,
                            width: 3,
                          );
                        }
                        return BorderSide.none;
                      }),
                      elevation: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.focused)) return 6;
                        return 0;
                      }),
                    ),
                    onPressed: actionsEnabled ? _onSubmitPressed : null,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(buttonLabel),
                  ),
                ),
              ),
              if (showQrOption) ...[
                const SizedBox(width: 10),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(3),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: IconButton.outlined(
                      focusNode: _qrFocus,
                      tooltip: 'Sign in with QR code',
                      style: IconButton.styleFrom(shape: FladderTheme.largeShape),
                      onPressed: actionsEnabled ? _openQrSheet : null,
                      icon: const Icon(IconsaxPlusLinear.scan_barcode),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (showBackToPhone) ...[
            const SizedBox(height: 10),
            FocusTraversalOrder(
              order: const NumericFocusOrder(3.5),
              child: TextButton.icon(
                onPressed: actionsEnabled ? () => unawaited(_backToPhoneNumber()) : null,
                icon: const Icon(IconsaxPlusLinear.arrow_left_2, size: 18),
                label: const Text('Change phone number'),
              ),
            ),
          ],
          if (showBackToQr) ...[
            const SizedBox(height: 10),
            FocusTraversalOrder(
              order: const NumericFocusOrder(4),
              child: OutlinedButton.icon(
                focusNode: _backToQrFocus,
                style: OutlinedButton.styleFrom(
                  shape: FladderTheme.largeShape,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: actionsEnabled
                    ? () async {
                        setState(() => _busy = true);
                        try {
                          await widget.onBackToQr!();
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      }
                    : null,
                icon: const Icon(IconsaxPlusLinear.scan_barcode),
                label: const Text('Back to QR code'),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
