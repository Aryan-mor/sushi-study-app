import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fladder/sushi/sushi_splash_brand.dart';
import 'package:fladder/sushi/sushi_tdlib_bridge_controller.dart';
import 'package:fladder/util/localization_helper.dart';

/// Full-screen "we are actually working" experience shown while the first Telegram MTProto
/// connection for this device is establishing.
///
/// Confirmed on-device (2026-08-18, verbose gotd trace): the ~15-18s this takes is not network —
/// it is CPU-bound Diffie-Hellman key generation (big-integer modular exponentiation) for a fresh
/// MTProto auth key, which is unusually slow on this class of TV hardware. A bare spinner reads as
/// frozen for that whole stretch, so this cycles a typewriter-animated set of status lines instead
/// — the same trick modern AI-agent UIs use to keep a genuinely-working wait from feeling stuck.
///
/// Deliberately no back/cancel affordance: the operation underneath is bounded by the caller's own
/// timeout (submitBotToken's ~100s ceiling — see _kAuthRpcTimeout in
/// sushi_tdlib_bridge_controller.dart) and always resolves to either success (the caller stops
/// rendering this) or a thrown SushiTdlibBridgeException the caller's own error UI handles with
/// Retry — so there is no state this screen could trap someone in longer than that ceiling.
///
/// This exact reconnect also happens right after the user taps Log out (native tears down the
/// session, then has to establish a brand new one before the login screen can even show a QR/phone
/// form) — showing the same "signing you in" narrative there read as wrong to someone who just
/// asked to sign OUT. See [SushiTdlibBridgeController.justLoggedOut]: this widget picks a
/// distinct logout-flavored phrase set for that one reconnect cycle.
class SushiTdlibConnectingExperience extends StatefulWidget {
  const SushiTdlibConnectingExperience({super.key});

  /// True for as long as an instance of this widget is mounted anywhere. The login screen it
  /// lives inside watches this to hide its own chrome (switch-user button/FAB) while a takeover
  /// screen is up — a small escape hatch peeking through around the edges would defeat the point
  /// of "no back/cancel" documented above. A counter (not a plain bool) because the phone/QR
  /// panels can briefly mount a second instance while swapping state before the old one disposes.
  static final ValueNotifier<bool> isActive = ValueNotifier(false);
  static int _activeCount = 0;

  @override
  State<SushiTdlibConnectingExperience> createState() => _SushiTdlibConnectingExperienceState();
}

class _SushiTdlibConnectingExperienceState extends State<SushiTdlibConnectingExperience> {
  static const _charInterval = Duration(milliseconds: 45);
  static const _holdDuration = Duration(milliseconds: 1300);
  static const _fadeDuration = Duration(milliseconds: 220);

  Timer? _charTimer;
  Timer? _holdTimer;
  int _phraseIndex = 0;
  int _charCount = 0;
  bool _visible = true;

  /// Captured once at mount, not re-read per build: this reconnect either was or wasn't
  /// logout-triggered for its whole duration, and re-checking mid-animation could otherwise flip
  /// the phrase list out from under an in-progress typewriter cycle.
  late final bool _isPostLogout = SushiTdlibBridgeController.instance().justLoggedOut;

  List<String> _phrases(BuildContext context) {
    final loc = context.localized;
    if (_isPostLogout) {
      return [
        loc.sushiLoggingOutPhrase1,
        loc.sushiLoggingOutPhrase2,
        loc.sushiLoggingOutPhrase3,
        loc.sushiLoggingOutPhrase4,
        loc.sushiLoggingOutPhrase5,
        loc.sushiLoggingOutPhrase6,
        loc.sushiLoggingOutPhrase7,
        loc.sushiLoggingOutPhrase8,
      ];
    }
    return [
      loc.sushiConnectingPhrase1,
      loc.sushiConnectingPhrase2,
      loc.sushiConnectingPhrase3,
      loc.sushiConnectingPhrase4,
      loc.sushiConnectingPhrase5,
      loc.sushiConnectingPhrase6,
      loc.sushiConnectingPhrase7,
      loc.sushiConnectingPhrase8,
    ];
  }

  @override
  void initState() {
    super.initState();
    SushiTdlibConnectingExperience._activeCount++;
    SushiTdlibConnectingExperience.isActive.value = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _typeCurrentPhrase());
  }

  void _typeCurrentPhrase() {
    if (!mounted) return;
    _charTimer?.cancel();
    _charCount = 0;
    final length = _phrases(context)[_phraseIndex % 8].length;
    _charTimer = Timer.periodic(_charInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_charCount >= length) {
        timer.cancel();
        _holdTimer = Timer(_holdDuration, _advancePhrase);
        return;
      }
      setState(() => _charCount++);
    });
  }

  void _advancePhrase() {
    if (!mounted) return;
    setState(() => _visible = false);
    Timer(_fadeDuration, () {
      if (!mounted) return;
      setState(() {
        _phraseIndex++;
        _visible = true;
      });
      _typeCurrentPhrase();
    });
  }

  @override
  void dispose() {
    _charTimer?.cancel();
    _holdTimer?.cancel();
    SushiTdlibConnectingExperience._activeCount--;
    if (SushiTdlibConnectingExperience._activeCount <= 0) {
      SushiTdlibConnectingExperience._activeCount = 0;
      SushiTdlibConnectingExperience.isActive.value = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phrases = _phrases(context);
    final current = phrases[_phraseIndex % phrases.length];
    final shown = current.substring(0, _charCount.clamp(0, current.length));

    return PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SushiSplashBrand(),
            const SizedBox(height: 36),
            SizedBox(
              height: 28,
              width: double.infinity,
              child: AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: _fadeDuration,
                child: Text(
                  shown,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
