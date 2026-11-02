import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fladder/sushi/sushi_dotenv.dart';
import 'package:fladder/sushi/sushi_login_kind_store.dart';
import 'package:fladder/sushi/sushi_tdlib_bridge_controller.dart';
import 'package:fladder/sushi/sushi_tdlib_connecting_experience.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_local_account.dart';
import 'package:fladder/sushi/sushi_login_channel.dart';
import 'package:fladder/sushi/sushi_login_seal.dart';

/// Sign-in without a personal Telegram user session (Sushi channel path, ADR 0013).
///
/// Open main-bot (`?start=ac_<nonce>`), poll `t.me/s/exampleLoginChannel` while focused.
/// No paste.
class SushiMainBotLoginPanel extends ConsumerStatefulWidget {
  const SushiMainBotLoginPanel(
      {required this.onSuccess,
      this.onBack,
      this.wide = false,
      this.logo,
      super.key});

  final Future<void> Function() onSuccess;
  final VoidCallback? onBack;

  /// Big screens / TV: render as two side-by-side panes — logo + hint on the start
  /// side, QR + Open-Telegram action on the end side — instead of one stacked column.
  final bool wide;

  /// Shown at the top of the start-side pane when [wide]. The screen passes its own
  /// (hold-to-demo–wrapped) logo so that gesture survives this layout.
  final Widget? logo;

  @override
  ConsumerState<SushiMainBotLoginPanel> createState() =>
      _SushiMainBotLoginPanelState();
}

class _SushiMainBotLoginPanelState
    extends ConsumerState<SushiMainBotLoginPanel>
    with WidgetsBindingObserver {
  final _http = http.Client();
  String? _error;
  bool _starting = false;
  bool _finishing = false;
  bool _waiting = false;
  Uint8List? _nonce;
  DateTime? _deadline;
  Timer? _pollTimer;

  /// Sushi: whether this device has a Telegram app to hand off to. When false the QR is the
  /// only way forward, so it is shown immediately (see [_detectTelegram]).
  bool _telegramInstalled = true;

  /// Sushi: the user asked to sign in from their phone — render [_qrPayloadUrl] as a QR code
  /// instead of only offering the "Open Telegram" hand-off on this device.
  bool _showQr = false;

  /// The `https://t.me/<mainbot>?start=ac_<nonce>` URL backing both the hand-off and the QR.
  String? _qrPayloadUrl;

  static const _focusPoll = Duration(seconds: 2);
  // BotFather setup can take hours. Match loginpost.TTL so the channel post is still there.
  static const _giveUp = Duration(hours: 8);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_detectTelegram());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _http.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _armFocusPoll(immediate: true);
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  String _sushiInitbotNotReady(SushiAssignment assignment) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    if (assignment.notPublic) return sushiNotPublicMessage(fa: fa);
    final blob = assignment.rawReply.toLowerCase();
    if (blob.contains('user_is_bot') ||
        blob.contains("can't send messages to other bots")) {
      return fa
          ? 'باتت هنوز نمی‌تونه به بات سوشی پیام بده. تو @BotFather مینی‌اپ رو باز کن (یا پایین صفحه دکمهٔ Open رو بزن)، باتت رو انتخاب کن، Bot Settings، بعد Bot to Bot Communication Mode رو روشن کن. بعد دوباره ورود رو بزن.'
          : 'Your bot cannot message Sushi bots yet. In @BotFather open the Mini App (or tap Open at the bottom), pick your bot, Bot Settings, and turn on Bot to Bot Communication Mode. Then tap Login again.';
    }
    return fa
        ? 'هنوز آماده نیست. تو تلگرام راهنما رو تموم کن، بعد برگرد اپ.'
        : 'Not ready yet. Finish setup in Telegram, then come back to the app.';
  }

  void _armFocusPoll({required bool immediate}) {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_waiting || _finishing || _nonce == null) return;
    if (immediate) {
      unawaited(_tickChannel());
    }
    _pollTimer = Timer.periodic(_focusPoll, (_) => unawaited(_tickChannel()));
  }

  Future<void> _tickChannel() async {
    if (!mounted || !_waiting || _finishing) return;
    final nonce = _nonce;
    final deadline = _deadline;
    if (nonce == null || deadline == null) return;
    if (DateTime.now().isAfter(deadline)) {
      _pollTimer?.cancel();
      _pollTimer = null;
      final fa = Localizations.localeOf(context).languageCode == 'fa';
      setState(() {
        _waiting = false;
        _error = fa
            ? 'لاگین طول کشید. دوباره تلگرام رو باز کن.'
            : 'Sign-in took too long. Open Telegram again.';
      });
      return;
    }
    try {
      final token = await sushiPollLoginChannel(_http, nonce);
      if (!mounted || token == null) return;
      _pollTimer?.cancel();
      _pollTimer = null;
      await _submitSushiBotToken(token);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = sushiTdlibAuthUserMessage(e));
    }
  }

  Future<void> _submitSushiBotToken(String token) async {
    if (_finishing) return;
    setState(() {
      _finishing = true;
      _error = null;
    });
    try {
      await SushiTdlibBridgeController.instance()
          .ensureBotTokenSession(token);
      final assignment = await sushiRunInitbotAfterTdlibReady();
      if (assignment.pending || assignment.apiSendTargets.isEmpty) {
        throw StateError(_sushiInitbotNotReady(assignment));
      }
      final account = await sushiEnsureLocalAccount(ref);
      await SushiLoginKindStore.save(
          accountId: account.id, kind: SushiLoginKind.bot);
      await widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _finishing = false;
        _waiting = false;
        if (e is StateError) {
          _error = e.message;
        } else {
          _error = sushiTdlibAuthUserMessage(e);
        }
      });
    }
  }

  Future<void> _openMainBotForAppCode() => _startAppCodeAttempt(launch: true);

  Future<void> _showQrForAppCode() async {
    // Reuse the in-flight attempt if there is one — minting a fresh nonce would orphan a code
    // the user may have already opened in Telegram.
    if (_waiting && _qrPayloadUrl != null) {
      setState(() => _showQr = true);
      return;
    }
    setState(() => _showQr = true);
    await _startAppCodeAttempt(launch: false);
  }

  Future<void> _startAppCodeAttempt({required bool launch}) async {
    await SushiDotenv.ensureLoaded();
    final nonce = sushiNewLoginNonce();
    final payload = sushiLoginStartPayload(nonce);
    final url = SushiConfig.mainBotAppCodeUrl(payload);
    setState(() {
      _nonce = nonce;
      _deadline = DateTime.now().add(_giveUp);
      _waiting = true;
      _error = null;
      _qrPayloadUrl = url;
    });
    if (launch) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
    if (!mounted) return;
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _armFocusPoll(immediate: true);
    }
  }

  /// If this device has no Telegram app, "Open Telegram" is a dead end — surface the QR right
  /// away so the user can finish from their phone. Relies on the `tg` scheme being declared in
  /// AndroidManifest `<queries>` / iOS `LSApplicationQueriesSchemes` for the probe to work.
  Future<void> _detectTelegram() async {
    var installed = true;
    try {
      installed = await canLaunchUrl(
        Uri.parse('tg://resolve?domain=${SushiConfig.mainBotUsername}'),
      );
    } catch (_) {
      installed = true; // probe not permitted — assume present; the hand-off still works
    }
    if (!mounted) return;
    setState(() => _telegramInstalled = installed);
    if (!installed) unawaited(_showQrForAppCode());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_finishing || _starting) {
      // Post-auth: the token is in, now bringing the bot session up + running the
      // initbot handshake before Home. This is a genuine multi-second wait the user
      // opted into, so use the typewriter "setting up" experience, not a bare spinner.
      return const SushiTdlibConnectingExperience();
    }

    return _buildSushi(theme);
  }

  static const _sushiSalmon = Color(0xFFE37A42);

  ButtonStyle get _sushiFill => FilledButton.styleFrom(
        backgroundColor: _sushiSalmon,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _sushiSalmon.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white70,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        minimumSize: const Size.fromHeight(52),
      );

  Widget _buildSushi(ThemeData theme) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    if (widget.wide) {
      // Big screens / TV: logo + numbered hint on the start side, QR + Open-Telegram
      // action on the end side, instead of one tall stacked column.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.logo != null) ...[
                  widget.logo!,
                  const SizedBox(height: 24),
                ],
                ..._sushiIntro(theme, fa),
              ],
            ),
          ),
          const SizedBox(width: 40),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _sushiActions(theme, fa, muted),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._sushiIntro(theme, fa),
        const SizedBox(height: 20),
        ..._sushiActions(theme, fa, muted),
      ],
    );
  }

  /// Title + the three numbered setup steps — the "hint" half of the panel.
  List<Widget> _sushiIntro(ThemeData theme, bool fa) {
    return [
      Text(
        fa ? 'ورود با بات خودت' : 'Sign in with a bot you own',
        style: theme.textTheme.titleLarge,
        textAlign: widget.wide ? TextAlign.start : TextAlign.center,
      ),
      const SizedBox(height: 12),
      _sushiStep(
          theme,
          fa ? '۱' : '1',
          fa
              ? 'دکمهٔ نارنجی رو بزن، یا با آیکن QR از گوشیت وارد شو.'
              : 'Tap Open Telegram — or use the QR icon to sign in from your phone.'),
      _sushiStep(
          theme,
          fa ? '۲' : '2',
          fa
              ? 'اگه بات نداری تو BotFather بساز، Bot-to-Bot رو روشن کن، توکن رو همون‌جا ریپلای کن.'
              : 'If you need a bot: create one in BotFather, turn on Bot-to-Bot, reply with the token there.'),
      _sushiStep(
          theme,
          fa ? '۳' : '3',
          fa
              ? 'وقتی گفت لاگین شدی، برگرد اینجا. اپ خودش وارد می‌شه.'
              : 'When it says you are in, come back here. Sushi signs you in.'),
    ];
  }

  /// QR / Open-Telegram controls, the "use my account instead" back link and any
  /// error — the interactive half of the panel.
  List<Widget> _sushiActions(ThemeData theme, bool fa, TextStyle? muted) {
    return [
      if (_showQr && _qrPayloadUrl != null) ...[
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: _qrPayloadUrl!,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          fa
              ? 'با دوربین گوشیت این کد رو اسکن کن تا تلگرام باز بشه. این صفحه رو باز نگه دار؛ اپ خودش وارد می‌شه.'
              : 'Scan this with your phone to open Telegram. Keep this screen open — Sushi signs you in automatically.',
          style: muted,
          textAlign: TextAlign.center,
        ),
        if (_waiting) ...[
          const SizedBox(height: 8),
          Text(
            fa ? 'منتظر تلگرام…' : 'Waiting for Telegram…',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
        if (_telegramInstalled) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () {
              setState(() => _showQr = false);
              if (!_waiting) unawaited(_openMainBotForAppCode());
            },
            icon: const Icon(IconsaxPlusLinear.send_2, size: 18),
            label: Text(fa
                ? 'باز کردن تلگرام روی همین دستگاه'
                : 'Open Telegram on this device'),
          ),
        ],
      ] else ...[
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                autofocus: true,
                style: _sushiFill,
                onPressed:
                    _waiting ? null : () => unawaited(_openMainBotForAppCode()),
                icon: const Icon(IconsaxPlusLinear.send_2),
                label: Text(_waiting
                    ? (fa ? 'منتظر تلگرام…' : 'Waiting for Telegram…')
                    : (fa ? 'باز کردن تلگرام' : 'Open Telegram')),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 52,
              height: 52,
              child: IconButton.outlined(
                tooltip: fa
                    ? 'نمایش کد QR برای ورود از گوشی'
                    : 'Show a QR code to sign in from your phone',
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ).copyWith(
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.focused)) {
                      return const BorderSide(color: _sushiSalmon, width: 3);
                    }
                    return BorderSide(color: theme.colorScheme.outline);
                  }),
                ),
                onPressed: () => unawaited(_showQrForAppCode()),
                icon: const Icon(IconsaxPlusLinear.scan_barcode),
              ),
            ),
          ],
        ),
      ],
      if (widget.onBack != null) ...[
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(IconsaxPlusLinear.arrow_left_2, size: 18),
          label: Text(fa
              ? 'با اکانت تلگرام وارد شو'
              : 'Use my Telegram account instead'),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(
          _error!,
          textAlign: TextAlign.center,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: muted?.copyWith(color: theme.colorScheme.error) ??
              TextStyle(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => unawaited(
            _showQr ? _showQrForAppCode() : _openMainBotForAppCode(),
          ),
          child: Text(fa ? 'تلاش دوباره' : 'Try again'),
        ),
      ],
    ];
  }

  Widget _sushiStep(ThemeData theme, String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: _sushiSalmon, shape: BoxShape.circle),
            child: Text(
              n,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(text, style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}
