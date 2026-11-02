import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/sushi/sushi_bridge_file.dart';
import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/sushi/sushi_tdlib_session_cache.dart';
import 'package:fladder/sushi/sushi_telegram_windows_bridge_stub.dart'
    if (dart.library.io) 'package:fladder/sushi/sushi_telegram_windows_bridge.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

const _kSushiTdlibDeviceIdPrefsKey = 'sushi_td_device_id';
const _kSushiBotTokenPrefsKey = 'sushi_bot_token';
const _kTdlibAuthLogTag = 'sushi-tdlib-auth';

class SushiTdlibBridgeException implements Exception {
  SushiTdlibBridgeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Short user-facing auth errors — never [PlatformException.toString] (includes stacktrace).
String sushiTdlibAuthUserMessage(Object error) {
  final raw = switch (error) {
    SushiTdlibBridgeException e => e.message,
    PlatformException e => (e.message?.trim().isNotEmpty == true) ? e.message!.trim() : e.code,
    _ => error.toString(),
  };
  final upper = raw.toUpperCase();
  if (upper.contains('PHONE_CODE_INVALID') || upper.contains('PHONE_CODE_EMPTY')) {
    return 'Wrong code. Try again.';
  }
  if (upper.contains('PHONE_CODE_EXPIRED')) {
    return 'Code expired. Go back and request a new one.';
  }
  if (upper.contains('PHONE_NUMBER_INVALID') || upper.contains('PHONE_NUMBER_FLOOD')) {
    return upper.contains('FLOOD')
        ? 'Too many attempts. Wait a bit, then try again.'
        : 'Invalid phone number. Include country code (e.g. +98…).';
  }
  if (upper.contains('AUTH_TOKEN_EXPIRED') || upper.contains('AUTH_TOKEN_INVALID')) {
    return 'That QR code expired. Scan the new one.';
  }
  if (upper.contains('PASSWORD_HASH_INVALID') ||
      upper.contains('PASSWORD_EMPTY') ||
      upper.contains('INVALID PASSWORD')) {
    return 'Wrong two-factor password.';
  }
  if (upper.contains('FLOOD_WAIT') || upper.contains('TOO_MANY_REQUESTS')) {
    return 'Too many attempts. Wait a bit, then try again.';
  }
  if (upper.contains('NETWORK') ||
      upper.contains('TIMEOUT') ||
      upper.contains('TIMED OUT') ||
      upper.contains('CONNECTION') ||
      upper.contains('COULD NOT REACH TELEGRAM')) {
    return 'Could not reach Telegram. Check internet / VPN and try again.';
  }
  // Strip PlatformException / TdlibException wrappers if any slipped through.
  final cleaned = raw
      .replaceFirst(RegExp(r'^PlatformException\([^,]*,\s*'), '')
      .replaceFirst(RegExp(r'^TdlibException:\s*'), '')
      .split(',')
      .first
      .trim();
  if (cleaned.length > 140) {
    return '${cleaned.substring(0, 140)}…';
  }
  return cleaned.isEmpty ? 'Something went wrong. Try again.' : cleaned;
}

/// Thin controller wrapping SushiTdlibBridgeApi (Android Pigeon) or Windows gotd FFI host.
/// One instance per app process.
class SushiTdlibBridgeController extends ChangeNotifier implements SushiTdlibBridgeEvents {
  SushiTdlibBridgeController._() {
    if (!sushiTelegramUseWindowsHost()) {
      SushiTdlibBridgeEvents.setUp(this);
    }
    if (sushiTelegramUseWindowsHost()) {
      _windows = SushiTelegramWindowsBridge(onAuthStateChanged: onAuthStateChanged);
    }
  }

  static SushiTdlibBridgeController? _instance;

  factory SushiTdlibBridgeController.instance() {
    return _instance ??= SushiTdlibBridgeController._();
  }

  final _api = SushiTdlibBridgeApi();
  SushiTelegramWindowsBridge? _windows;
  SushiTdlibAuthState _state = SushiTdlibAuthState(kind: SushiTdlibAuthStateKind.uninitialized);
  SushiTdlibConnectionHealth _health = SushiTdlibConnectionHealth.uninitialized;
  bool _configured = false;
  /// Login-screen prepare/reset must not silently [submitBotToken] from cache.
  /// That would land TDLib on [SushiTdlibAuthStateKind.ready] and the phone/QR UI
  /// would never appear (checkmark only).
  bool _suppressBotSessionRestore = false;

  /// True for the one reconnect cycle immediately following THIS device's own logOut() —
  /// [SushiTdlibConnectingExperience] reads this once at mount to pick logout-flavored copy
  /// ("Signing you out…") instead of the generic connect narrative, since the same widget covers
  /// both a cold app start and a post-logout reconnect and the two read very differently to
  /// someone who just tapped Log out. Set synchronously by [clearSessionAfterSushiLogout] (see its
  /// doc for why it can't wait for the native `closed` event); cleared once the reconnect surfaces
  /// real interactive UI (QR/code/password/ready/failed) so a later, unrelated reconnect doesn't
  /// inherit stale copy.
  bool _justLoggedOut = false;
  bool get justLoggedOut => _justLoggedOut;

  bool get _useWindows => _windows != null;

  SushiTdlibAuthState get state => _state;

  /// Socket liveness, independent of [state] — see [SushiTdlibConnectionHealth].
  ///
  /// Windows drives playback through its own bridge and does not report health, so it stays at
  /// [SushiTdlibConnectionHealth.uninitialized] there; treat that value as "unknown, don't block".
  SushiTdlibConnectionHealth get connectionHealth => _health;

  /// True when credentials are valid but the socket is not usable right now.
  ///
  /// The native side is already retrying with backoff when this is true, so it is a "show a
  /// transient notice / wait" signal — never a reason to send the user back to login. Only
  /// [SushiTdlibAuthStateKind.failed] means the credentials themselves need replacing.
  bool get isConnectionDegraded =>
      _state.kind == SushiTdlibAuthStateKind.ready && _health == SushiTdlibConnectionHealth.degraded;

  /// True when a login exists AND its connection can carry a playback download.
  ///
  /// `uninitialized` health counts as usable so this never blocks the Windows bridge or a build
  /// whose native side predates health reporting: playback then fails the old way (a real error
  /// from the download call) rather than being refused by a gate that has no information.
  bool get canStartPlayback =>
      _state.kind == SushiTdlibAuthStateKind.ready && _health != SushiTdlibConnectionHealth.degraded;

  /// True when THIS RUN called submitBotToken (fresh login or a Dart-driven cache restore). False
  /// on a warm app start where native silently resumed a persisted bot session from disk without
  /// Dart's involvement — see [isNativeSessionActuallyBot] for the accurate check. Kept for the
  /// existing UI-only call sites (settings badge, telemetry tag) where that staleness is harmless.
  bool get nativeSessionIsBot => _activeBotToken != null && _activeBotToken!.isNotEmpty;

  /// Ground truth from the native side (mobile.Client.IsBotMode / gotd AuthController), accurate
  /// even when the current session was restored from disk at configure() without Dart ever calling
  /// submitBotToken this run — the case [nativeSessionIsBot] gets wrong. Use this, not the getter
  /// above, for anything that decides whether playback can proceed: getting it wrong is what let a
  /// stale restored bot session pass the reader-sync mismatch check and hang forever waiting on a
  /// push the backend was sending to the account's linked Telegram session instead.
  ///
  /// Falls back to [nativeSessionIsBot] if the native call itself fails — no worse than the old
  /// behavior, not a new failure mode.
  Future<bool> isNativeSessionActuallyBot() async {
    try {
      if (_useWindows) return _windows!.isNativeSessionBot();
      return await _api.isNativeSessionBot();
    } catch (e) {
      _log('isNativeSessionActuallyBot failed: $e');
      return nativeSessionIsBot;
    }
  }

  Future<bool> hasCachedBotToken() async {
    if (nativeSessionIsBot) return true;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kSushiBotTokenPrefsKey);
    return cached != null && cached.isNotEmpty;
  }

  /// True once TDLib finished setTdlibParameters and is ready for phone/QR/code/password.
  bool get isReadyForAuthInput => _isInteractiveAuthKind(_state.kind);

  /// True while a human-facing login flow (phone/code/2FA/QR) is actively waiting on user input,
  /// OR could be about to start one (freshly configured, about to request a QR/phone step) —
  /// narrower than "not ready", which also covers the legitimate "nobody is doing anything with
  /// this client right now" case that a silent bot-token bootstrap is meant for. Callers that
  /// might otherwise repoint the shared native client onto a different identity (e.g.
  /// sushiEnsureTdlibMatchesUser's bot-token bootstrap, which — per ensureBotTokenSession's
  /// doc — tears down or redirects whatever session is currently there) must check this first, or
  /// they race a login screen that is actively mid-flow on the same client.
  ///
  /// [waitingForPhoneNumber] is included even though it's also the natural "fresh device" resting
  /// state: confirmed live (2026-08-18) that the race isn't limited to the QR-shown window — an
  /// unrelated dashboard-prefetch call landed in this exact window (state still
  /// waitingForPhoneNumber, a QR request already in flight from the login screen but not yet
  /// reflected) and still corrupted the session, with the QR goroutine's still-running refresh
  /// timer failing moments later with BOT_METHOD_INVALID. The one caller this costs
  /// (sushi_main_bot_login_panel's opportunistic bot-link right after its own sign-in) already
  /// documents itself as best-effort with a playback-time re-check, so skipping it here is safe.
  bool get isInteractiveLoginInProgress {
    switch (_state.kind) {
      case SushiTdlibAuthStateKind.waitingForPhoneNumber:
      case SushiTdlibAuthStateKind.waitingForCode:
      case SushiTdlibAuthStateKind.waitingForPassword:
      case SushiTdlibAuthStateKind.waitingForQrConfirmation:
        return true;
      case SushiTdlibAuthStateKind.uninitialized:
      case SushiTdlibAuthStateKind.ready:
      case SushiTdlibAuthStateKind.failed:
      case SushiTdlibAuthStateKind.loggingOut:
      case SushiTdlibAuthStateKind.closed:
        return false;
    }
  }

  static bool _isInteractiveAuthKind(SushiTdlibAuthStateKind kind) {
    switch (kind) {
      case SushiTdlibAuthStateKind.waitingForPhoneNumber:
      case SushiTdlibAuthStateKind.waitingForCode:
      case SushiTdlibAuthStateKind.waitingForPassword:
      case SushiTdlibAuthStateKind.waitingForQrConfirmation:
      case SushiTdlibAuthStateKind.ready:
      case SushiTdlibAuthStateKind.failed:
        return true;
      case SushiTdlibAuthStateKind.uninitialized:
      case SushiTdlibAuthStateKind.loggingOut:
      case SushiTdlibAuthStateKind.closed:
        return false;
    }
  }

  void _log(String message) {
    developer.log(message, name: _kTdlibAuthLogTag);
    if (kDebugMode) {
      debugPrint('[$_kTdlibAuthLogTag] $message');
    }
  }

  @override
  void onAuthStateChanged(SushiTdlibAuthState state) {
    if (state.kind != _state.kind ||
        state.errorMessage != _state.errorMessage) {
      _log(
        'state → ${state.kind.name}'
        '${state.qrLoginUrl != null ? ' qrUrl=${state.qrLoginUrl!.length}c' : ''}'
        '${state.errorMessage != null ? ' err=${state.errorMessage}' : ''}',
      );
    }
    _state = state;
    if (state.kind == SushiTdlibAuthStateKind.uninitialized ||
        state.kind == SushiTdlibAuthStateKind.closed) {
      _configured = false;
    }
    if (_justLoggedOut &&
        state.kind != SushiTdlibAuthStateKind.uninitialized &&
        state.kind != SushiTdlibAuthStateKind.loggingOut &&
        state.kind != SushiTdlibAuthStateKind.closed &&
        state.kind != SushiTdlibAuthStateKind.waitingForPhoneNumber) {
      // Real interactive UI is about to show (QR/code/password/ready/failed) — this reconnect
      // cycle is over. [clearSessionAfterSushiLogout] is what sets this true in the first place.
      _justLoggedOut = false;
    }
    notifyListeners();
  }

  @override
  void onConnectionHealthChanged(SushiTdlibConnectionHealth health) {
    if (_health == health) return;
    _log('connection health → ${health.name} (auth=${_state.kind.name})');
    _health = health;
    notifyListeners();
  }

  /// Revives a dead connection, returning whether playback can proceed afterwards.
  ///
  /// Cheap and safe to call on every play: the native side no-ops when the socket is already
  /// healthy. A false result means the connection could not be re-established — a network problem
  /// to report as such, NOT a reason to prompt for login, since the credentials were never in
  /// question (see [isConnectionDegraded]).
  Future<bool> ensureConnected() async {
    // Windows drives its own connection lifecycle through SushiTelegramWindowsBridge and exposes no
    // health signal; there is nothing to revive from here.
    if (_useWindows) return _state.kind == SushiTdlibAuthStateKind.ready;
    if (_state.kind != SushiTdlibAuthStateKind.ready &&
        _state.kind != SushiTdlibAuthStateKind.failed) {
      return false;
    }
    if (_health == SushiTdlibConnectionHealth.ready &&
        _state.kind == SushiTdlibAuthStateKind.ready) {
      return true;
    }
    try {
      await _api.reconnect();
      _health = await _api.connectionHealth();
      _state = await _api.currentAuthState();
      _log('ensureConnected → health=${_health.name} auth=${_state.kind.name}');
      notifyListeners();
      return _state.kind == SushiTdlibAuthStateKind.ready &&
          _health != SushiTdlibConnectionHealth.degraded;
    } catch (e) {
      _log('ensureConnected failed: $e');
      return false;
    }
  }

  /// Serializes concurrent ensureConfigured callers onto one in-flight attempt instead of each
  /// kicking off its own native configure/restore — confirmed a real bug: several
  /// dashboard-slider items prefetching at once each raced their own bot-token restore
  /// (ensureBotSessionFromCacheIfNeeded → submitBotToken) against the others, and the native
  /// side losing that race would reset to uninitialized, which the next prefetch's
  /// ensureConfigured then saw and "fixed" by reconfiguring — repeating forever, and starving
  /// the real play action of a state that ever settled.
  Future<void>? _ensureConfiguredInFlight;

  /// Bumped by [clearSessionAfterSushiLogout] so an in-flight [waitUntilReadyForAuthInput]
  /// that started against the old client aborts instead of polling `uninitialized` for 45s
  /// after native `logOut` nulls the client (Pixel 10 Pro, 2026-09-20).
  int _configureEpoch = 0;

  /// Idempotent — safe to call from every login panel's initState, and from every prefetch/play
  /// attempt (see _ensureConfiguredInFlight — concurrent callers share one attempt).
  /// Waits until TDLib accepts phone/QR input (past setTdlibParameters) — for bot-mode sessions,
  /// also tries to restore a previously-connected bot from local cache if the native state isn't
  /// already ready (see ensureBotSessionFromCacheIfNeeded), so both prefetch and the real play
  /// action see the same, fully-restored state without either needing to know about the other.
  Future<void> ensureConfigured({
    Duration readyTimeout = const Duration(seconds: 45),
  }) {
    final pendingSignOut = _pendingIntentionalSignOut;
    if (pendingSignOut != null) {
      _log('ensureConfigured: awaiting in-flight sign-out');
      return pendingSignOut.then((_) => ensureConfigured(readyTimeout: readyTimeout));
    }
    final inFlight = _ensureConfiguredInFlight;
    if (inFlight != null) return inFlight;
    final future = _ensureConfiguredLocked(readyTimeout);
    _ensureConfiguredInFlight = future;
    future.whenComplete(() {
      if (identical(_ensureConfiguredInFlight, future)) {
        _ensureConfiguredInFlight = null;
      }
    });
    return future;
  }

  Future<void> _ensureConfiguredLocked(Duration readyTimeout) async {
    final epoch = _configureEpoch;
    if (_configured) {
      // Don't trust the cached flag alone — re-verify against native's actual current state.
      // Observed in practice: _configured stays true (this singleton survives Dart hot restarts)
      // while native's auth state regresses to uninitialized, with nothing left to call
      // configure() again and drive it forward — waitUntilReadyForAuthInput then polls a dead
      // state for the full timeout instead of failing fast or self-healing.
      final polled = _useWindows ? _windows!.currentAuthState() : await _api.currentAuthState();
      // `closed` / `loggingOut` are a torn-down session, not a live client to keep polling.
      // Treating them like `ready` sat on Connecting… for 45s after Settings → Log out
      // (Pixel 10 Pro, 2026-09-20): native already nulled the client.
      if (!_needsNativeRecreate(polled.kind)) {
        _state = polled;
        await waitUntilReadyForAuthInput(timeout: readyTimeout);
        if (epoch != _configureEpoch) return;
        await _restoreBotSessionIfNeededLocked();
        return;
      }
      // `failed` after a live session is usually a dropped MTProto engine, not missing
      // credentials. reconnect() rebuilds gotd; re-submitBotToken on that corpse is what
      // looped `engine was closed` on Pixel 10 Pro (2026-09-19).
      if (polled.kind == SushiTdlibAuthStateKind.failed && !_useWindows) {
        _log('ensureConfigured: native failed — reconnect before bot-token restore');
        _state = polled;
        if (await ensureConnected() &&
            _state.kind == SushiTdlibAuthStateKind.ready) {
          return;
        }
      }
      // `failed` is treated exactly like `uninitialized`, not like a configured state. It is what
      // native lands in when a cold-start RPC fails, and it used to be cached the same way `ready`
      // was: every later play logged "already configured kind=failed" and never retried, so the
      // app stayed dead until it was force-killed (seen on Xiaomi).
      //
      // This used to also force a real logOut() here first ("configure() is idempotent on already
      // have a client, so without teardown it returns the same dead client straight back") — true
      // when the connection itself is still alive (go/oxtelegram/client.go's Configure only
      // rebuilds when the run loop actually died), but that teardown is the same destructive
      // AuthLogOut RPC prepareForLoginScreen's stuck-at path used to call, and hits the same
      // problem: it silently signs out an already-authenticated user to recover from what may
      // just be a transient failure, with no confirmation. There is no non-destructive "drop this
      // client object but keep the on-disk session" primitive exposed to Dart yet (only
      // reconnect()/logOut()) — go/oxtelegram/mobile's Client.Close() is exactly that, but isn't
      // wired through pigeons/tdlib_bridge.dart. Until it is, just reconfigure without the
      // teardown: if the client really is dead this no-ops and `failed` surfaces as a normal
      // thrown SushiTdlibBridgeException below (see prepareForLoginScreen), which shows Retry —
      // and the user's own explicit "log out" action (resetStuckSession) is the deliberate,
      // confirmed path if retries don't help.
      _log('ensureConfigured: cached configured=true but native reports ${polled.kind.name} — reconfiguring');
      _configured = false;
    }
    final apiId = SushiEnv.telegramApiId;
    final apiHash = SushiEnv.telegramApiHash;
    if (apiId == null || apiHash == null) {
      throw SushiTdlibBridgeException(
        'TELEGRAM_API_ID/TELEGRAM_API_HASH not configured for this build',
      );
    }
    _log('ensureConfigured: calling native configure apiId=$apiId');
    if (_useWindows) {
      await _windows!.configure(apiId, apiHash);
      _state = _windows!.currentAuthState();
    } else {
      await _api.configure(apiId, apiHash);
      _state = await _api.currentAuthState();
    }
    _configured = true;
    _log('ensureConfigured: currentAuthState=${_state.kind.name}');
    notifyListeners();
    await waitUntilReadyForAuthInput(timeout: readyTimeout);
    if (epoch != _configureEpoch) return;
    await _restoreBotSessionIfNeededLocked();
  }

  static bool _needsNativeRecreate(SushiTdlibAuthStateKind kind) {
    switch (kind) {
      case SushiTdlibAuthStateKind.uninitialized:
      case SushiTdlibAuthStateKind.failed:
      case SushiTdlibAuthStateKind.closed:
      case SushiTdlibAuthStateKind.loggingOut:
        return true;
      case SushiTdlibAuthStateKind.waitingForPhoneNumber:
      case SushiTdlibAuthStateKind.waitingForCode:
      case SushiTdlibAuthStateKind.waitingForPassword:
      case SushiTdlibAuthStateKind.waitingForQrConfirmation:
      case SushiTdlibAuthStateKind.ready:
        return false;
    }
  }

  /// Only ever called from inside _ensureConfiguredLocked (hence "Locked" — under the same
  /// single-flight guard as the rest of ensureConfigured, not a separate entry point). A no-op
  /// unless state is waitingForPhoneNumber (fresh/unauthenticated) and a bot token is cached —
  /// see submitBotToken's caching and ensureBotSessionFromCacheIfNeeded's fuller doc comment.
  Future<void> _restoreBotSessionIfNeededLocked() async {
    if (_suppressBotSessionRestore && _state.kind != SushiTdlibAuthStateKind.ready) {
      _log('restoreBotSession: skipped (login-screen auth)');
      return;
    }
    await ensureBotSessionFromCacheIfNeeded();
  }

  /// Blocks until past WaitTdlibParameters (phone/QR/code/password/ready/failed).
  /// Polls native state — do not rely only on pigeon events (hot restart drops in-flight pushes).
  Future<void> waitUntilReadyForAuthInput({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_isInteractiveAuthKind(_state.kind)) {
      return;
    }

    _log('waitUntilReadyForAuthInput: polling (now=${_state.kind.name})');
    final epoch = _configureEpoch;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (epoch != _configureEpoch) {
        _log('waitUntilReadyForAuthInput: aborted (sign-out)');
        return;
      }
      final polled = _useWindows ? _windows!.currentAuthState() : await _api.currentAuthState();
      if (polled.kind != _state.kind) {
        _log('waitUntilReadyForAuthInput: polled ${polled.kind.name}');
      }
      _state = polled;
      if (_isInteractiveAuthKind(polled.kind)) {
        notifyListeners();
        _log('waitUntilReadyForAuthInput: ready kind=${polled.kind.name}');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    notifyListeners();
    throw SushiTdlibBridgeException(
      'Telegram client did not finish initializing (stuck at ${_state.kind.name}). Try again.',
    );
  }

  /// Call from login-screen bootstrap before showing any auth UI.
  /// Blocks the splash until TDLib is past setTdlibParameters.
  /// When [phoneFirst] is true (phone/tablet), aborts a leftover QR session so the
  /// phone field is usable immediately.
  ///
  /// Does not destroy an already-`ready` Telegram session on a hunch — it used to ("OX logout
  /// does not always clear Telegram"), which is the same bug class as the stuck-timeout one
  /// below: an uncertain/inferred signal treated as confirmed. The one legitimate case that
  /// comment was guarding (an OX-triggered sign-out whose Telegram-side clear hasn't landed yet)
  /// is now handled precisely, by awaiting [_pendingIntentionalSignOut] instead of guessing.
  Future<void> prepareForLoginScreen({bool phoneFirst = true}) async {
    _log('prepareForLoginScreen phoneFirst=$phoneFirst');
    _suppressBotSessionRestore = true;
    try {
      // Must finish the OX sign-out's native logOut+close BEFORE configure. The other order
      // (configure first, await sign-out after) is what stuck login on Connecting… after
      // Settings → Log out: Kotlin configure short-circuited on the still-live client, then
      // logOut nulled it, and Dart polled `uninitialized` for 45s (Pixel 10 Pro, 2026-09-20).
      final pendingSignOut = _pendingIntentionalSignOut;
      if (pendingSignOut != null) {
        _log('prepareForLoginScreen: awaiting in-flight intentional sign-out');
        await pendingSignOut;
      }
      // A "stuck at <kind>" SushiTdlibBridgeException from ensureConfigured propagates as-is
      // — this used to auto-recover by force-calling logOut() on the real Telegram session, which
      // also fires on an ordinary cold launch whose first connect is merely slow (e.g. waking from
      // background after several minutes), silently signing out an already-authenticated user.
      // Recovery is now the caller's call: show the error with a Retry action (re-runs this
      // method) and a separate, user-confirmed "log out" action — see resetStuckSession().
      await ensureConfigured();
      if (phoneFirst && _state.kind == SushiTdlibAuthStateKind.waitingForQrConfirmation) {
        await resetForPhoneLogin();
      }
      if (_state.kind == SushiTdlibAuthStateKind.failed) {
        throw SushiTdlibBridgeException(
          _state.errorMessage ?? 'Telegram auth failed to start',
        );
      }
      if (!_isInteractiveAuthKind(_state.kind)) {
        throw SushiTdlibBridgeException(
          'Telegram client did not finish initializing (stuck at ${_state.kind.name}). Try again.',
        );
      }
      // `ready` here (with no sign-out pending above) means Telegram genuinely still holds a
      // valid session — arriving at the login screen despite that means something ELSE (a
      // cleared OX account, e.g.) put us here, not a stale/leftover Telegram login. Destroying a
      // real session to "fix" that used to be exactly the bug this rewrite closes (see this
      // method's top-of-file doc): don't. SushiTdlibLoginPanel already watches for `ready` and
      // completes the OX sign-in exchange itself once this returns and the panel mounts.
      _log('prepareForLoginScreen done kind=${_state.kind.name}');
    } finally {
      _suppressBotSessionRestore = false;
    }
  }

  /// User-confirmed reset of a native Telegram client that failed to finish initializing or
  /// landed in a failed auth state (either surfaces as an SushiTdlibBridgeException from
  /// prepareForLoginScreen). Only call this after the user has
  /// explicitly opted into logging out via a destructive-action dialog — see
  /// sushi_login_screen.dart's error-state UI. Callers must re-run prepareForLoginScreen
  /// afterward (e.g. by re-invoking the same bootstrap that called it originally).
  Future<void> resetStuckSession() async {
    _log('resetStuckSession: user-confirmed logOut + recreate');
    _configured = false;
    try {
      if (_useWindows) {
        await _windows!.logOut();
      } else {
        await _api.logOut();
      }
    } catch (logoutErr) {
      _log('resetStuckSession: logOut threw: $logoutErr');
    }
  }

  /// True when [restartApp] has a real implementation to call (Android only — see
  /// TdlibBridgeObject.kt's restartApp; Windows has no equivalent).
  bool get canRestartApp => !_useWindows;

  /// Kills and relaunches the whole app process — never returns on success. Session storage is
  /// untouched (not a logout); see restartApp's doc in pigeons/tdlib_bridge.dart for why this,
  /// not a plain reconfigure, is what actually recovers a stuck/failed native client reliably:
  /// go/oxtelegram/client.go's Configure() no-ops on "already have a live client object" even one
  /// whose auth landed in `failed`, so an in-process retry can end up doing nothing.
  Future<void> restartApp() async {
    if (!canRestartApp) {
      throw SushiTdlibBridgeException('App restart is not available on this platform.');
    }
    _log('restartApp: requesting process restart');
    await _api.restartApp();
  }

  /// Must stay above mobile.authCallTimeout (90s in go/oxtelegram/mobile/bind.go) or the native
  /// side's budget for a data-centre migration is unreachable — this deadline would fire first and
  /// report a timeout while the login was still legitimately in flight. The 45s that used to be
  /// here did exactly that on a slow TV link.
  static const _kAuthRpcTimeout = Duration(seconds: 100);

  static bool _isPastPhoneStep(SushiTdlibAuthStateKind kind) {
    switch (kind) {
      case SushiTdlibAuthStateKind.waitingForCode:
      case SushiTdlibAuthStateKind.waitingForPassword:
      case SushiTdlibAuthStateKind.ready:
        return true;
      default:
        return false;
    }
  }

  /// Race [rpc] against [until] / timeout so flaky Telegram DCs cannot hang the UI forever.
  Future<void> _awaitAuthRpc(
    Future<void> rpc, {
    required bool Function(SushiTdlibAuthStateKind kind) until,
    required String timeoutMessage,
  }) async {
    if (until(_state.kind)) return;

    final advanced = Completer<void>();
    void onState() {
      if (until(_state.kind) && !advanced.isCompleted) {
        advanced.complete();
      }
    }

    addListener(onState);
    try {
      await Future.any<void>([rpc, advanced.future]).timeout(
        _kAuthRpcTimeout,
        onTimeout: () => throw SushiTdlibBridgeException(timeoutMessage),
      );
    } finally {
      removeListener(onState);
    }
  }

  Future<void> submitPhoneNumber(String phoneNumber) async {
    final trimmed = phoneNumber.trim();
    _log('submitPhoneNumber len=${trimmed.length} kind=${_state.kind.name}');
    if (trimmed.isEmpty) {
      throw SushiTdlibBridgeException('Enter a phone number with country code');
    }
    if (_state.kind != SushiTdlibAuthStateKind.waitingForPhoneNumber) {
      throw SushiTdlibBridgeException(
        'Telegram is not ready for phone login yet (state=${_state.kind.name})',
      );
    }
    await _awaitAuthRpc(
      _useWindows ? _windows!.submitPhoneNumber(trimmed) : _api.submitPhoneNumber(trimmed),
      until: _isPastPhoneStep,
      timeoutMessage:
          'Could not reach Telegram (timed out). Check internet / VPN and try again.',
    );
  }

  /// Bot-token login: an alternative to phone/QR for users who don't want to give Sushi
  /// access to their personal Telegram account. Goes straight to `ready` — no code/2FA step.
  /// Everything downstream (state, startPlaybackSession, stopPlaybackSession, logOut) is
  /// unchanged by which of the two paths got here — callers never need to know or branch on it.
  /// Native (auth.go SubmitBotToken/checkInitialStatus) has no state restriction on when this can
  /// be called — a transient RPC failure at cold start (checkInitialStatus's Auth().Status call,
  /// or a previous SubmitBotToken attempt) lands in `failed`, and calling this again from there is
  /// exactly how ensureBotSessionFromCacheIfNeeded recovers (see its widened guard below).
  Future<void> submitBotToken(String token) async {
    final trimmed = token.trim();
    if (_state.kind != SushiTdlibAuthStateKind.ready) {
      _log('submitBotToken len=${trimmed.length} kind=${_state.kind.name}');
    }
    if (trimmed.isEmpty) {
      throw SushiTdlibBridgeException('Enter your bot token');
    }
    // Restored bot sessions are already `ready` but Auth.BotToken() is empty, so MTProto
    // sendMessage returns USER_IS_BOT. Native SubmitBotToken hydrates the in-memory token.
    final hydrateReadyBot = _state.kind == SushiTdlibAuthStateKind.ready &&
        await isNativeSessionActuallyBot();
    if (_state.kind != SushiTdlibAuthStateKind.waitingForPhoneNumber && !hydrateReadyBot) {
      throw SushiTdlibBridgeException(
        'Telegram is not ready for bot-token login yet (state=${_state.kind.name})',
      );
    }
    if (hydrateReadyBot) {
      if (_useWindows) {
        await _windows!.submitBotToken(trimmed);
      } else {
        await _api.submitBotToken(trimmed);
      }
    } else {
      await _awaitAuthRpc(
        _useWindows ? _windows!.submitBotToken(trimmed) : _api.submitBotToken(trimmed),
        until: (kind) => kind == SushiTdlibAuthStateKind.ready,
        timeoutMessage:
            'Could not reach Telegram (timed out). Check internet / VPN and try again.',
      );
    }
    _activeBotToken = trimmed;
    // Cached so a later app start (or a fresh install's first playback attempt) can silently
    // re-apply it via ensureBotSessionFromCacheIfNeeded, without needing the OX session/access
    // token threaded all the way down here again.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSushiBotTokenPrefsKey, trimmed);
  }

  String? _activeBotToken;
  Future<void>? _ensureBotTokenInFlight;
  String? _ensureBotTokenTarget;

  /// Logs native TDLib in as [token] (personal bot). Tears down a leftover user/QR session first —
  /// [submitBotToken] only accepts `waitingForPhoneNumber`, so a previous client-session login
  /// otherwise stays `ready` while the API copies into `@userbot`. Play then waits 20s on the
  /// wrong account.
  Future<void> ensureBotTokenSession(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return Future.error(SushiTdlibBridgeException('Enter your bot token'));
    }
    if (_state.kind == SushiTdlibAuthStateKind.ready && _activeBotToken == trimmed) {
      return Future.value();
    }
    if (_ensureBotTokenInFlight != null && _ensureBotTokenTarget == trimmed) {
      return _ensureBotTokenInFlight!;
    }
    final future = _ensureBotTokenSessionLocked(trimmed);
    _ensureBotTokenInFlight = future;
    _ensureBotTokenTarget = trimmed;
    future.whenComplete(() {
      if (identical(_ensureBotTokenInFlight, future)) {
        _ensureBotTokenInFlight = null;
        _ensureBotTokenTarget = null;
      }
    });
    return future;
  }

  Future<void> _ensureBotTokenSessionLocked(String trimmed) async {
    if (_state.kind == SushiTdlibAuthStateKind.ready && _activeBotToken == trimmed) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSushiBotTokenPrefsKey, trimmed);

    // Restored bot session is already ready. Hydrate the in-memory Bot API token; do not
    // logOut + Auth().Bot (that closed gotd's engine on Pixel 10 Pro, 2026-09-19).
    if (_state.kind == SushiTdlibAuthStateKind.ready &&
        await isNativeSessionActuallyBot()) {
      _log('ensureBotTokenSession: hydrate ready bot session');
      await submitBotToken(trimmed);
      return;
    }

    _log('ensureBotTokenSession: switching to personal bot from kind=${_state.kind.name}');

    Future<void> tearDownNativeSession() async {
      try {
        await logOut();
      } catch (e) {
        _log('ensureBotTokenSession: logOut: $e');
      }
      _configured = false;
      _activeBotToken = null;
    }

    if (_state.kind != SushiTdlibAuthStateKind.waitingForPhoneNumber) {
      await tearDownNativeSession();
      await ensureConfigured();
    }
    if (_state.kind == SushiTdlibAuthStateKind.ready && _activeBotToken == trimmed) {
      return;
    }
    if (_state.kind != SushiTdlibAuthStateKind.waitingForPhoneNumber) {
      await tearDownNativeSession();
      await ensureConfigured();
    }
    if (_state.kind == SushiTdlibAuthStateKind.ready && _activeBotToken == trimmed) {
      return;
    }
    if (_state.kind != SushiTdlibAuthStateKind.waitingForPhoneNumber) {
      throw SushiTdlibBridgeException(
        'Telegram is not ready for bot-token login yet (state=${_state.kind.name})',
      );
    }
    await submitBotToken(trimmed);
  }

  /// Re-applies a cached BotFather token so Bot API sendMessage works.
  ///
  /// A disk-restored bot session is already `ready` with [IsBotMode] true, but
  /// [AuthController.BotToken] is empty until this runs (or native sidecar persist loads it).
  /// Skipping that hydrate (2026-09-19) sent `/initbot` over MTProto and Telegram answered
  /// `USER_IS_BOT` — Bot-to-Bot mode is HTTP Bot API only, not `messages.sendMessage`.
  ///
  /// Hydrate is `SubmitBotToken` without `Auth().Bot`: native `hydrateBotTokenIfAuthorized`
  /// stores the token in memory. Calling `Auth().Bot` on a live session closed the RPC engine.
  ///
  /// Also retries from `failed`: a transient cold-start RPC hiccup (checkInitialStatus's
  /// Auth().Status) lands native in `failed`, and _ensureConfiguredLocked used to skip
  /// reconfigure — the app then reported "bot isn't connected" on every play.
  Future<void> ensureBotSessionFromCacheIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kSushiBotTokenPrefsKey);
    if (cached == null || cached.isEmpty) return;

    if (_state.kind == SushiTdlibAuthStateKind.ready) {
      if (_activeBotToken == cached) return;
      if (!await isNativeSessionActuallyBot()) return;
      try {
        await submitBotToken(cached);
      } catch (e) {
        _log('ensureBotSessionFromCacheIfNeeded: hydrate failed: $e');
      }
      return;
    }
    if (_state.kind != SushiTdlibAuthStateKind.waitingForPhoneNumber &&
        _state.kind != SushiTdlibAuthStateKind.failed) {
      return;
    }
    try {
      await submitBotToken(cached);
    } catch (e) {
      _log('ensureBotSessionFromCacheIfNeeded: cached token no longer works: $e');
    }
  }

  Future<void> submitCode(String code) async {
    await _awaitAuthRpc(
      _useWindows ? _windows!.submitCode(code) : _api.submitCode(code),
      until: (kind) =>
          kind == SushiTdlibAuthStateKind.waitingForPassword ||
          kind == SushiTdlibAuthStateKind.ready,
      timeoutMessage:
          'Could not verify code (timed out). Check internet / VPN and try again.',
    );
  }

  Future<void> submitTwoFactorPassword(String password) async {
    await _awaitAuthRpc(
      _useWindows ? _windows!.submitTwoFactorPassword(password) : _api.submitTwoFactorPassword(password),
      until: (kind) => kind == SushiTdlibAuthStateKind.ready,
      timeoutMessage:
          'Could not verify password (timed out). Check internet / VPN and try again.',
    );
  }

  Future<void> requestQrLogin() async {
    _log('requestQrLogin (current=${_state.kind.name})');
    await waitUntilReadyForAuthInput();
    if (_state.kind != SushiTdlibAuthStateKind.waitingForPhoneNumber &&
        _state.kind != SushiTdlibAuthStateKind.waitingForQrConfirmation) {
      throw SushiTdlibBridgeException(
        'Cannot start QR login from state=${_state.kind.name}',
      );
    }
    if (_useWindows) {
      return _windows!.requestQrLogin();
    }
    return _api.requestQrLogin();
  }

  Future<void> logOut() => _useWindows ? _windows!.logOut() : _api.logOut();

  /// True when TDLib finished AuthorizationStateReady (persisted user session on device).
  ///
  /// Used on cold start to keep OX sessions that already completed Telegram sign-in, while
  /// forcing re-login for legacy bot/deep-link OX sessions that have no MTProto session.
  /// Fail-open on configure/init errors so a transient Telegram outage does not wipe OX tokens.
  Future<bool> hasReadyUserSession({
    Duration readyTimeout = const Duration(seconds: 25),
  }) async {
    // Windows configure() is a synchronous FFI call. Dart timers cannot fire while it
    // blocks the UI isolate — splash freezes forever if Telegram DCs are unreachable
    // (common on upgrade from a pre-TDLib login that still has a saved OX account).
    // Session file presence is enough to decide splash: init the client after home.
    if (_useWindows) {
      final persisted = await _windows!.hasPersistedSessionFile();
      _log('hasReadyUserSession: windows session.bin=$persisted (skip configure)');
      return persisted;
    }
    try {
      await ensureConfigured(readyTimeout: readyTimeout);
    } catch (e) {
      _log('hasReadyUserSession: ensureConfigured failed ($e) — fail-open');
      return true;
    }
    final kind = _state.kind;
    if (kind == SushiTdlibAuthStateKind.ready) {
      _log('hasReadyUserSession: ready');
      return true;
    }
    if (kind == SushiTdlibAuthStateKind.failed) {
      // `failed` settles as a normal, non-throwing return from ensureConfigured (see
      // waitUntilReadyForAuthInput's _isInteractiveAuthKind) — it means the native client
      // couldn't determine its own state, not that this account was ever unauthenticated.
      // Confirmed on-device (2026-08-17): the same slow-connect race that lands `failed` here
      // hit this exact branch and, before this fix, made sushiResolveSplashAuth locally sign
      // an already-authenticated user out on every cold start it lost that race. Same fail-open
      // as a thrown exception above, for the same reason: never a reason to wipe OX tokens.
      _log('hasReadyUserSession: failed — fail-open (not the same as no session)');
      return true;
    }
    // No completed Telegram user session (or mid-login leftover) — a clean, non-error state.
    _log('hasReadyUserSession: not ready kind=${kind.name}');
    return false;
  }

  /// Tracks an in-flight [clearSessionAfterSushiLogout] so [prepareForLoginScreen] can deterministically
  /// wait for a genuinely-intentional sign-out instead of guessing one happened from Telegram's
  /// reported state — see prepareForLoginScreen's doc for the bug this replaced.
  Future<void>? _pendingIntentionalSignOut;

  /// OX account sign-out: wipe Telegram session without re-warming the client.
  /// Login screen [prepareForLoginScreen] / [ensureConfigured] starts a fresh client later.
  ///
  /// `auth_provider.dart`'s logOutUser() calls this via sushiLogoutTelegramSession()
  /// unawaited (a blocking Telegram logOut() would make the OX "log out" action feel frozen),
  /// so the login screen can legitimately render before this finishes — see
  /// [_pendingIntentionalSignOut].
  ///
  /// Sets [_justLoggedOut] synchronously, right here, rather than reactively off the native
  /// `closed` event: that event arrives only after the unawaited logOut() RPC round-trips, by
  /// which point the login screen (and its connecting-experience widget) has often already
  /// mounted and captured a stale "not a logout" reading. Confirmed live (2026-08-18): the
  /// connecting screen kept showing generic connect copy after a real Settings → Log out because
  /// of exactly that race.
  Future<void> clearSessionAfterSushiLogout() {
    _justLoggedOut = true;
    final future = _clearSessionAfterSushiLogoutLocked();
    _pendingIntentionalSignOut = future;
    future.whenComplete(() {
      if (identical(_pendingIntentionalSignOut, future)) {
        _pendingIntentionalSignOut = null;
      }
    });
    return future;
  }

  Future<void> _clearSessionAfterSushiLogoutLocked() async {
    _log('clearSessionAfterSushiLogout from kind=${_state.kind.name}');
    _configureEpoch++;
    _ensureConfiguredInFlight = null;
    try {
      await logOut();
    } catch (e) {
      _log('clearSessionAfterSushiLogout logOut error (continuing): $e');
    }
    _configured = false;
    await clearCachedBotToken();
    _state = SushiTdlibAuthState(kind: SushiTdlibAuthStateKind.uninitialized);
    notifyListeners();
  }

  /// Drops the BotFather token used to restore a bot session after process death.
  Future<void> clearCachedBotToken() async {
    _activeBotToken = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSushiBotTokenPrefsKey);
    } catch (e) {
      _log('clearCachedBotToken prefs: $e');
    }
  }

  /// Abort QR (or any mid-auth) and recreate client so phone login works again.
  Future<void> resetForPhoneLogin() async {
    _log('resetForPhoneLogin from kind=${_state.kind.name}');
    final previousSuppress = _suppressBotSessionRestore;
    _suppressBotSessionRestore = true;
    try {
      try {
        await logOut();
      } catch (e) {
        _log('resetForPhoneLogin logOut error (continuing): $e');
      }
      _configured = false;
      await clearCachedBotToken();
      _state = SushiTdlibAuthState(kind: SushiTdlibAuthStateKind.uninitialized);
      notifyListeners();
      await ensureConfigured();
    } finally {
      _suppressBotSessionRestore = previousSuppress;
    }
  }

  /// Resolves a PlaybackInfo Telegram source and starts progressive download.
  ///
  /// Throws [SushiTdlibBridgeException] with a clear, user-facing message — not a raw native
  /// PlatformException/AUTH_KEY_UNREGISTERED stack trace — when the native session isn't
  /// authenticated at all. That used to be silently attempted anyway (a real bug: a bot-mode
  /// user's native bridge only ever got configured right after a fresh login, never again on
  /// later app starts, so returning users hit the native call with kind still
  /// waitingForPhoneNumber and got an opaque AUTH_KEY_UNREGISTERED crash instead of a clear
  /// "reconnect your bot" message).
  Future<String> startPlaybackSession(SushiTdlibPlaybackSource source) async {
    // ensureConfigured already tries the cached-bot-token restore (see
    // _restoreBotSessionIfNeededLocked) — under the same single-flight guard every other
    // concurrent caller (prefetch included) shares, so this doesn't race a separate attempt.
    await ensureConfigured(readyTimeout: const Duration(seconds: 180));
    if (_state.kind != SushiTdlibAuthStateKind.ready) {
      throw SushiTdlibBridgeException(
        "Your personal bot isn't connected. In Telegram, send /connectbot to "
        "@${SushiEnv.botUsername ?? 'main-bot'} to reconnect it, then try again.",
      );
    }
    if (_useWindows) {
      return _windows!.startPlaybackSession(source);
    }
    return _api.startPlaybackSession(source);
  }

  /// Where the native session actually read [locator], or null. Reported to the backend so the
  /// next play of the same file skips the copy — see SushiTelegramDeliveryApi. Never throws: a
  /// failure here only costs one redundant copy.
  Future<SushiTdlibDeliveryRef?> deliveryRefForLocator(String locator) async {
    try {
      if (_useWindows) {
        return _windows!.deliveryRefForLocator(locator);
      }
      return await _api.deliveryRefForLocator(locator);
    } catch (e) {
      _log('deliveryRefForLocator failed: $e');
      return null;
    }
  }

  /// Registers interest in [locator] BEFORE the PlaybackInfo call that triggers the copy, so a
  /// delivery landing while that request is still in flight is captured rather than raced for.
  /// Never throws — the native buffer already tolerates an unarmed early arrival, this only
  /// narrows the window.
  Future<void> armDeliveryWaiter(String locator) async {
    if (locator.isEmpty) return;
    try {
      if (_useWindows) {
        _windows!.armDeliveryWaiter(locator);
      } else {
        await _api.armDeliveryWaiter(locator);
      }
    } catch (e) {
      _log('armDeliveryWaiter failed: $e');
    }
  }

  /// Resolves [source] and records where it landed WITHOUT opening a download — the warm-up path.
  /// Requires a ready session, like [startPlaybackSession], but deliberately starts no byte
  /// transfer: warming a dashboard row must not spend the user's data on a dozen videos nobody
  /// pressed play on.
  Future<void> warmDelivery(SushiTdlibPlaybackSource source) async {
    await ensureConfigured(readyTimeout: const Duration(seconds: 60));
    if (_state.kind != SushiTdlibAuthStateKind.ready) return;
    if (_useWindows) {
      await _windows!.warmDelivery(source);
      return;
    }
    await _api.warmDelivery(source);
  }

  /// Blocks until the session is [SushiTdlibAuthStateKind.ready] (user logged in, not merely past
  /// setTdlibParameters). Distinct from [waitUntilReadyForAuthInput], which returns at
  /// waitingForPhoneNumber — too early to startBot.
  Future<bool> waitUntilSessionReady({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_state.kind == SushiTdlibAuthStateKind.ready) return true;
    final done = Completer<void>();
    void onState() {
      if (_state.kind == SushiTdlibAuthStateKind.ready && !done.isCompleted) {
        done.complete();
      }
    }
    addListener(onState);
    try {
      await done.future.timeout(timeout);
    } on TimeoutException {
      _log('waitUntilSessionReady timed out kind=${_state.kind.name}');
    } finally {
      removeListener(onState);
    }
    return _state.kind == SushiTdlibAuthStateKind.ready;
  }

  /// Starts, mutes and archives every delivery sender on this account so delivery copies never
  /// land in the user's visible inbox. Called on every app enter — a sender can be added to the
  /// backend's list at any time, and a user who never re-logs in would otherwise never start it.
  ///
  /// Returns false when the session is not ready (caller must retry, not mark the job done).
  /// Never throws: a failed startBot on one sender must not take playback down.
  Future<bool> ensureProviderBotsReady(List<SushiTdlibProviderBot> bots) async {
    if (bots.isEmpty) return true;
    try {
      await ensureConfigured(readyTimeout: const Duration(seconds: 60));
      if (_state.kind != SushiTdlibAuthStateKind.ready) {
        final ready = await waitUntilSessionReady();
        if (!ready) {
          _log('ensureProviderBotsReady skipped — auth kind=${_state.kind.name}');
          return false;
        }
      }
      if (_useWindows) {
        await _windows!.ensureProviderBotsReady(bots);
      } else {
        await _api.ensureProviderBotsReady(bots);
      }
      _log('ensureProviderBotsReady ok for ${bots.length} bot(s)');
      return true;
    } catch (e) {
      _log('ensureProviderBotsReady failed: $e');
      return false;
    }
  }

  Future<void> stopPlaybackSession(String sessionUri) async {
    // Belt and braces: SushiTdlibSessionCache refuses to store session-bound urls in the first
    // place, so this normally clears nothing. Kept so that a resolved url reaching the cache by any
    // future path still cannot outlive the session being torn down here.
    SushiTdlibSessionCache.clearAll();
    if (_useWindows) {
      await _windows!.stopPlaybackSession(sessionUri);
    } else {
      await _api.stopPlaybackSession(sessionUri);
    }
  }

  /// Fetches a Telegram-signed Mini App initData payload for TELEGRAM_WEBAPP_BOT_USERNAME (falls
  /// back to SUSHI_MAIN_BOT when no dedicated auth bot is configured).
  Future<String> fetchWebAppInitData() async {
    final botUsername = SushiEnv.telegramWebAppBotUsername;
    if (botUsername == null) {
      throw SushiTdlibBridgeException('TELEGRAM_WEBAPP_BOT_USERNAME not configured');
    }
    final path = _useWindows
        ? await _windows!.fetchWebAppInitData(
            botUsername,
            SushiEnv.telegramWebAppShortName,
            SushiEnv.telegramHostedWebAppHttpsUrl,
          )
        : await _api.fetchWebAppInitData(
            botUsername,
            SushiEnv.telegramWebAppShortName,
            SushiEnv.telegramHostedWebAppHttpsUrl,
          );
    return sushiReadBridgeFile(path);
  }

  /// DMs [username] with [text]; waits for next `!` framed reply (Sushi /initbot).
  Future<String> sendTextAndWaitReply({
    required String username,
    required String text,
    int timeoutMs = 30000,
  }) async {
    await ensureConfigured(readyTimeout: const Duration(seconds: 60));
    if (_state.kind != SushiTdlibAuthStateKind.ready) {
      throw SushiTdlibBridgeException('Telegram session not ready for sendTextAndWaitReply');
    }
    final path = _useWindows
        ? await _windows!.sendTextAndWaitReply(username, text, timeoutMs)
        : await _api.sendTextAndWaitReply(username, text, timeoutMs);
    return sushiReadBridgeFile(path);
  }

  /// Downloads a whole small document (a subtitle file, doc 15 §7) from this session's own chat.
  /// Returns the absolute path of the file, not its bytes — see the Pigeon spec. Callers that
  /// want the text go through [sushiFetchSmallDocument], which reads and deletes the file.
  Future<String> fetchSmallDocument({
    required int botId,
    required int messageId,
    required String locator,
    int timeoutMs = 30000,
  }) async {
    await ensureConfigured(readyTimeout: const Duration(seconds: 60));
    if (_state.kind != SushiTdlibAuthStateKind.ready) {
      throw SushiTdlibBridgeException('Telegram session not ready for fetchSmallDocument');
    }
    if (_useWindows) {
      return _windows!.fetchSmallDocument(botId, messageId, locator, timeoutMs);
    }
    return _api.fetchSmallDocument(botId, messageId, locator, timeoutMs);
  }

  /// Writes the thumbnail of the video delivered at [messageId] to [outPath] (a personal video's
  /// card, ADR 0037 §6). Throws when there is none; the caller keeps its placeholder.
  Future<void> fetchDocumentThumb({
    required int messageId,
    required String locator,
    required String outPath,
    int providerBotId = 0,
    int timeoutMs = 15000,
  }) async {
    await ensureConfigured(readyTimeout: const Duration(seconds: 60));
    if (_state.kind != SushiTdlibAuthStateKind.ready) {
      throw SushiTdlibBridgeException('Telegram session not ready for fetchDocumentThumb');
    }
    if (_useWindows) {
      return _windows!.fetchDocumentThumb(providerBotId, messageId, locator, outPath, timeoutMs);
    }
    return _api.fetchDocumentThumb(providerBotId, messageId, locator, outPath, timeoutMs);
  }

  /// DMs [username] with [text] without waiting for a reply (Sushi `/ack`, future watch-progress
  /// reports) — see the Pigeon spec for why this must never be used for a call whose reply the
  /// caller actually needs. Android/mobile only for now — the Windows FFI bridge does not export
  /// this yet.
  Future<void> sendTextFireAndForget({
    required String username,
    required String text,
  }) async {
    await ensureConfigured(readyTimeout: const Duration(seconds: 60));
    if (_state.kind != SushiTdlibAuthStateKind.ready) {
      throw SushiTdlibBridgeException('Telegram session not ready for sendTextFireAndForget');
    }
    if (_useWindows) return;
    return _api.sendTextFireAndForget(username, text);
  }

  /// Clicks a session account through main-bot's onboarding conversation (Sushi /initbot).
  /// Android/mobile only for now — the Windows FFI bridge does not export this yet.
  Future<void> ensureMainBotOnboarded({
    required String username,
    int timeoutMs = 90000,
  }) async {
    await ensureConfigured(readyTimeout: const Duration(seconds: 60));
    if (_state.kind != SushiTdlibAuthStateKind.ready) {
      throw SushiTdlibBridgeException('Telegram session not ready for ensureMainBotOnboarded');
    }
    if (_useWindows) return;
    return _api.ensureMainBotOnboarded(username, timeoutMs);
  }

  static Future<String> resolveDeviceIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    var storedId = prefs.getString(_kSushiTdlibDeviceIdPrefsKey)?.trim() ?? '';
    if (storedId.isEmpty) {
      final random = Random.secure();
      final bytes = List<int>.generate(16, (_) => random.nextInt(256));
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      storedId = 'oxa-$hex';
      await prefs.setString(_kSushiTdlibDeviceIdPrefsKey, storedId);
    }
    return storedId;
  }
}
