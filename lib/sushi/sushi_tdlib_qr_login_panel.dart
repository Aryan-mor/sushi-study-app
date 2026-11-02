import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:fladder/sushi/sushi_tdlib_bridge_controller.dart';
import 'package:fladder/sushi/sushi_tdlib_connecting_experience.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_local_account.dart';
import 'package:fladder/theme.dart';

/// Telegram QR login token lifetime is ~30s (TDLib `auth.loginToken.expires`).
/// Countdown is display-only — gotd refreshes tokens itself and pushes a new URL via
/// auth state. Do NOT call [SushiTdlibBridgeController.requestQrLogin] on expiry:
/// that cancels the in-flight QR.Auth goroutine and races phone scans into
/// AuthLoginTokenMigrateTo failures.
const _kQrRefreshInterval = Duration(seconds: 30);

/// Android TV sign-in: QR-first (remote typing is bad UX). Optional [onUsePhoneNumber]
/// lets the user focus a button and switch to the phone panel. When TDLib is ready,
/// runs Sushi `/initbot` (no HTTP OX session exchange).
/// When [onNeedTwoFactorPassword] is set, 2FA is handed off to that callback (close QR
/// sheet / switch to phone panel) instead of showing the password field inline.
///
/// TODO(l10n): strings here are hardcoded pending ARB entries; follow the sushiLogin* key
/// convention used elsewhere once these are ready to localize.
class SushiTdlibQrLoginPanel extends ConsumerStatefulWidget {
  const SushiTdlibQrLoginPanel({
    required this.onSuccess,
    this.onUsePhoneNumber,
    this.onNeedTwoFactorPassword,
    super.key,
  });

  final Future<void> Function() onSuccess;

  /// TV: focused with D-pad — switches to phone-number panel.
  final Future<void> Function()? onUsePhoneNumber;

  /// Phone QR sheet / TV: leave QR UI so the phone login panel can show 2FA.
  final VoidCallback? onNeedTwoFactorPassword;

  @override
  ConsumerState<SushiTdlibQrLoginPanel> createState() => _SushiTdlibQrLoginPanelState();
}

class _SushiTdlibQrLoginPanelState extends ConsumerState<SushiTdlibQrLoginPanel> {
  final _controller = SushiTdlibBridgeController.instance();
  final _passwordController = TextEditingController();
  final _phoneOptionFocus = FocusNode();
  bool _sushiExchangeStarted = false;
  bool _exchangingWithSushiApi = false;
  bool _passwordBusy = false;
  bool _passwordVisible = false;
  bool _twoFactorHandedOff = false;
  bool _starting = false;
  bool _refreshingQr = false;
  bool _scanConfirming = false;
  String? _error;
  String? _shownQrUrl;
  Timer? _urlWaitTimer;
  Timer? _expiryTimer;
  Timer? _countdownTicker;
  Timer? _confirmWatchdog;
  int _qrRetryCount = 0;
  DateTime? _qrIssuedAt;
  int _secondsUntilRefresh = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A leftover-but-valid `ready` Telegram session can already be the state at mount now
      // (prepareForLoginScreen no longer force-resets one away — see its doc), in which case
      // _start()'s QR request is moot and _onStateChanged's ready/exchange handling — normally
      // only reached via a FUTURE transition its listener observes — needs a first, manual kick
      // for a transition that already happened before this panel existed to listen for it.
      if (_controller.state.kind == SushiTdlibAuthStateKind.ready) {
        _onStateChanged();
        return;
      }
      _start();
    });
  }

  @override
  void dispose() {
    _urlWaitTimer?.cancel();
    _expiryTimer?.cancel();
    _countdownTicker?.cancel();
    _confirmWatchdog?.cancel();
    _controller.removeListener(_onStateChanged);
    _passwordController.dispose();
    _phoneOptionFocus.dispose();
    super.dispose();
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[sushi-tdlib-auth] qr-panel: $message');
    }
  }

  void _armUrlWaitTimer() {
    _urlWaitTimer?.cancel();
    _urlWaitTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      final url = _controller.state.qrLoginUrl;
      final kind = _controller.state.kind;
      if (url != null && url.isNotEmpty) return;
      _log('QR URL still missing after 8s (kind=$kind) — retry #${_qrRetryCount + 1}');
      if (_qrRetryCount >= 3) {
        setState(() {
          _error =
              'QR code did not arrive from Telegram (state=$kind). Check network / try again.';
        });
        return;
      }
      _qrRetryCount++;
      unawaited(_requestQr());
    });
  }

  void _armExpiryRefresh() {
    _expiryTimer?.cancel();
    _countdownTicker?.cancel();
    _qrIssuedAt = DateTime.now();
    _secondsUntilRefresh = _kQrRefreshInterval.inSeconds;
    // Display-only countdown. gotd re-exports when the token expires and emits a new
    // waitingForQrConfirmation URL — we re-arm from _onStateChanged. No requestQrLogin.
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _qrIssuedAt == null) return;
      final left = _kQrRefreshInterval.inSeconds -
          DateTime.now().difference(_qrIssuedAt!).inSeconds;
      final clamped = left.clamp(0, _kQrRefreshInterval.inSeconds);
      setState(() {
        _secondsUntilRefresh = clamped;
        // At 0 show "Refreshing…" until gotd pushes the next URL (re-arms above).
        _refreshingQr = clamped == 0;
      });
    });
  }

  Future<void> _requestQr() async {
    try {
      await _controller.requestQrLogin();
      _armUrlWaitTimer();
    } catch (e) {
      _log('requestQrLogin failed: $e');
      if (mounted) setState(() => _error = sushiTdlibAuthUserMessage(e));
    }
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    setState(() => _error = null);
    try {
      await _controller.ensureConfigured();
      final existing = _controller.state.qrLoginUrl;
      if (existing != null && existing.isNotEmpty) {
        _log('already have qrLoginUrl (${existing.length}c)');
        _shownQrUrl = existing;
        _urlWaitTimer?.cancel();
        _armExpiryRefresh();
      } else {
        await _requestQr();
      }
    } catch (e) {
      _log('start failed: $e');
      if (mounted) setState(() => _error = sushiTdlibAuthUserMessage(e));
    } finally {
      _starting = false;
    }
  }

  void _onStateChanged() {
    if (!mounted) return;
    final state = _controller.state;
    final url = state.qrLoginUrl;
    _log('state=${state.kind.name} url=${url != null && url.isNotEmpty}');

    final confirming = state.kind == SushiTdlibAuthStateKind.waitingForQrConfirmation &&
        (url == null || url.isEmpty);
    if (confirming && !_scanConfirming) {
      _armConfirmWatchdog();
    } else if (!confirming) {
      _confirmWatchdog?.cancel();
    }
    _scanConfirming = confirming;

    if (url != null && url.isNotEmpty) {
      _urlWaitTimer?.cancel();
      _qrRetryCount = 0;
      final notice = state.errorMessage;
      final expiredNotice = notice != null &&
          notice.toUpperCase().contains('AUTH_TOKEN');
      if (url != _shownQrUrl) {
        _shownQrUrl = url;
        _armExpiryRefresh();
        _log('QR URL updated (${url.length}c) — refresh timer armed');
        if (expiredNotice) {
          setState(() => _error = sushiTdlibAuthUserMessage(notice));
          return;
        }
      } else if (expiredNotice) {
        setState(() => _error = sushiTdlibAuthUserMessage(notice));
        return;
      }
    }
    setState(() {});
    if (state.kind == SushiTdlibAuthStateKind.waitingForPassword &&
        widget.onNeedTwoFactorPassword != null &&
        !_twoFactorHandedOff) {
      _twoFactorHandedOff = true;
      _expiryTimer?.cancel();
      _countdownTicker?.cancel();
      _urlWaitTimer?.cancel();
      _confirmWatchdog?.cancel();
      _log('2FA required — handing off to phone login panel');
      widget.onNeedTwoFactorPassword!();
      return;
    }
    if (state.kind == SushiTdlibAuthStateKind.ready && !_sushiExchangeStarted) {
      _expiryTimer?.cancel();
      _countdownTicker?.cancel();
      _confirmWatchdog?.cancel();
      unawaited(_maybeStartSushiExchange());
    }
    if (state.kind == SushiTdlibAuthStateKind.failed) {
      final raw = state.errorMessage ?? 'Telegram auth failed';
      final friendly = sushiTdlibAuthUserMessage(raw);
      final upper = raw.toUpperCase();
      if (upper.contains('AUTH_TOKEN')) {
        // Should be rare after native recovery — still unstick UI + mint new QR.
        setState(() => _error = friendly);
        unawaited(_recoverFreshQr());
        return;
      }
      setState(() => _error = friendly);
    }
  }

  void _armConfirmWatchdog() {
    _confirmWatchdog?.cancel();
    _confirmWatchdog = Timer(const Duration(seconds: 20), () {
      if (!mounted) return;
      final state = _controller.state;
      final url = state.qrLoginUrl;
      if (state.kind != SushiTdlibAuthStateKind.waitingForQrConfirmation) return;
      if (url != null && url.isNotEmpty) return;
      _log('confirming stuck 20s — recovering fresh QR');
      setState(() => _error = 'Scan timed out. Scan the new QR code.');
      unawaited(_recoverFreshQr());
    });
  }

  Future<void> _recoverFreshQr() async {
    _confirmWatchdog?.cancel();
    try {
      final kind = _controller.state.kind;
      if (kind == SushiTdlibAuthStateKind.failed ||
          kind == SushiTdlibAuthStateKind.ready ||
          kind == SushiTdlibAuthStateKind.closed) {
        await _controller.resetForPhoneLogin();
      }
      await _controller.requestQrLogin();
      _armUrlWaitTimer();
    } catch (e) {
      _log('recoverFreshQr failed: $e');
      if (mounted) setState(() => _error = sushiTdlibAuthUserMessage(e));
    }
  }

  /// Guards the ready-triggered initbot against a restored *bot* session — see the phone-login
  /// panel's identical guard (sushi_tdlib_login_panel.dart) for the full explanation.
  Future<void> _maybeStartSushiExchange() async {
    if (_sushiExchangeStarted) return;
    if (await _controller.isNativeSessionActuallyBot()) {
      _log('ready state is a bot session, skipping exchange');
      return;
    }
    if (!mounted || _controller.state.kind != SushiTdlibAuthStateKind.ready || _sushiExchangeStarted) {
      return;
    }
    _sushiExchangeStarted = true;
    await _exchangeWithSushiInitbot();
  }

  Future<void> _exchangeWithSushiInitbot() async {
    setState(() {
      _exchangingWithSushiApi = true;
      _error = null;
    });
    try {
      final assignment = await sushiRunInitbotAfterTdlibReady();
      sushiEnsureAssignmentReady(assignment);
      await sushiEnsureLocalAccount(ref);
      await widget.onSuccess();
    } catch (e) {
      if (mounted) setState(() => _error = sushiTdlibAuthUserMessage(e));
    } finally {
      if (mounted) setState(() => _exchangingWithSushiApi = false);
    }
  }

  Future<void> _submitPassword() async {
    setState(() => _passwordBusy = true);
    try {
      await _controller.submitTwoFactorPassword(_passwordController.text);
    } catch (e) {
      if (mounted) setState(() => _error = sushiTdlibAuthUserMessage(e));
    } finally {
      if (mounted) setState(() => _passwordBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _controller.state;
    final liveUrl = state.qrLoginUrl;
    final qrUrl = (liveUrl != null && liveUrl.isNotEmpty) ? liveUrl : _shownQrUrl;
    // Native emits empty QR URL while Import runs after scan — keep last QR dimmed + spinner.
    final scanConfirming = state.kind == SushiTdlibAuthStateKind.waitingForQrConfirmation &&
        (liveUrl == null || liveUrl.isEmpty) &&
        (_shownQrUrl != null && _shownQrUrl!.isNotEmpty);

    if (qrUrl == null || qrUrl.isEmpty) {
      // No QR yet means the MTProto connection is still coming up. This used to be a bare
      // spinner, which on a slow network sat silent long enough to look hung — see the
      // experience widget's doc for why this needs the full screen, not just a notice.
      if (_error == null) {
        return const SushiTdlibConnectingExperience();
      }
    }

    if (state.kind == SushiTdlibAuthStateKind.ready) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(IconsaxPlusBold.tick_circle, size: 48, color: theme.colorScheme.primary),
            if (_exchangingWithSushiApi) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  _sushiExchangeStarted = true;
                  unawaited(_exchangeWithSushiInitbot());
                },
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Sign in with Telegram',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Open Telegram on your phone → Settings → Devices → Link Desktop Device, then scan this code.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        if (qrUrl != null && qrUrl.isNotEmpty) ...[
          Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (_refreshingQr || scanConfirming) ? 0.45 : 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: QrImageView(
                    data: qrUrl,
                    size: 240,
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              if (_refreshingQr || scanConfirming) const CircularProgressIndicator(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            scanConfirming
                ? 'Confirming on Telegram…'
                : _refreshingQr
                    ? 'Refreshing code…'
                    : 'Code refreshes in ${_secondsUntilRefresh}s',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        // Inline 2FA only when no hand-off callback (phone sheet / TV switch to LoginPanel).
        if (state.kind == SushiTdlibAuthStateKind.waitingForPassword &&
            widget.onNeedTwoFactorPassword == null) ...[
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _passwordController,
                  obscureText: !_passwordVisible,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.done,
                  autofocus: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Two-factor password',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: IconButton(
                      tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                      onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                      icon: Icon(
                        _passwordVisible ? IconsaxPlusLinear.eye_slash : IconsaxPlusLinear.eye,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _submitPassword(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 52,
                height: 52,
                child: IconButton.filled(
                  style: IconButton.styleFrom(shape: FladderTheme.largeShape),
                  onPressed: _passwordBusy ? null : _submitPassword,
                  icon: _passwordBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(IconsaxPlusLinear.arrow_right_3),
                ),
              ),
            ],
          ),
        ],
          if (widget.onUsePhoneNumber != null &&
            state.kind != SushiTdlibAuthStateKind.waitingForPassword) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            focusNode: _phoneOptionFocus,
            autofocus: true,
            style: OutlinedButton.styleFrom(
              shape: FladderTheme.largeShape,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () async {
              _expiryTimer?.cancel();
              _countdownTicker?.cancel();
              await widget.onUsePhoneNumber!();
            },
            icon: const Icon(IconsaxPlusLinear.call),
            label: const Text('Sign in with phone number'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _qrRetryCount = 0;
              setState(() => _error = null);
              unawaited(_recoverFreshQr());
            },
            child: const Text('Get new QR'),
          ),
        ],
      ],
    );
  }
}
