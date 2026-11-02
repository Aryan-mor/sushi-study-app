import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/sushi/sushi_tdlib_bridge_controller.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';
import 'package:fladder/sushi/sushi_assignment_pb.dart';
import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_wire.dart';

/// Assignment from init-bot (docs/02 §1, docs/03, proto `sushi.v1.Assignment`).
class SushiAssignment {
  const SushiAssignment({
    required this.apiBotUsername,
    required this.pool,
    required this.providerId,
    required this.bindingToken,
    required this.epoch,
    this.deliveryBots = const [],
    this.pending = false,
    this.msgType = 0,
    this.corr = 0,
    this.rawReply = '',
    this.payloadBase64 = '',
    this.isError = false,
  });

  /// Proto field 1 `api_bot_username` — Ready/fallback handle, not the sole send target (ADR 0011).
  final String apiBotUsername;

  /// Proto field 2 `pool` — protocol DMs round-robin across these handles (ADR 0011).
  final List<String> pool;

  /// Proto field 3 `provider_id` (int32).
  final int providerId;

  /// Proto field 4 `binding_token` as base64url (no pad).
  final String bindingToken;

  /// Proto field 5 `epoch` (uint32).
  final int epoch;

  /// Proto field 6 `delivery_bots` — the pool deliveryd round-robins across (docs/05 §6),
  /// pre-started alongside the API pool so a first play doesn't fail `400 chat not found`.
  final List<String> deliveryBots;

  /// True when `/initbot` could not complete (bridge missing / timeout / ERR / bad payload).
  final bool pending;

  /// Envelope `type` varint (15 = ASSIGNMENT, 14 = ERR).
  final int msgType;
  final int corr;
  final String rawReply;

  /// Raw protobuf payload (debug / round-trip). Optional.
  final String payloadBase64;
  final bool isError;

  static const int msgTypeErr = 14;
  static const int msgTypeAssignment = 15;

  /// Proto `ErrCode.ERR_CODE_NOT_PUBLIC`: registration is closed and this person has no account
  /// and no invite (server ADR 0039).
  static const int errCodeNotPublic = 8;
  static const int flagCompressed = 1 << 0;

  Map<String, dynamic> toJson() => {
        'apiBotUsername': apiBotUsername,
        'pool': pool,
        'providerId': providerId,
        'bindingToken': bindingToken,
        'epoch': epoch,
        'deliveryBots': deliveryBots,
        'pending': pending,
        'msgType': msgType,
        'corr': corr,
        'rawReply': rawReply,
        'payloadBase64': payloadBase64,
        'isError': isError,
      };

  factory SushiAssignment.fromJson(Map<String, dynamic> json) {
    final rawProvider = json['providerId'];
    final providerId =
        rawProvider is int ? rawProvider : int.tryParse('$rawProvider') ?? 0;
    return SushiAssignment(
      apiBotUsername: (json['apiBotUsername'] as String?) ?? '',
      pool: (json['pool'] as List?)?.map((e) => '$e').toList() ?? const [],
      providerId: providerId,
      bindingToken: (json['bindingToken'] as String?) ?? '',
      epoch: (json['epoch'] as num?)?.toInt() ?? 0,
      deliveryBots:
          (json['deliveryBots'] as List?)?.map((e) => '$e').toList() ??
              const [],
      pending: json['pending'] == true,
      msgType: (json['msgType'] as num?)?.toInt() ?? 0,
      corr: (json['corr'] as num?)?.toInt() ?? 0,
      rawReply: (json['rawReply'] as String?) ?? '',
      payloadBase64: (json['payloadBase64'] as String?) ?? '',
      isError: json['isError'] == true,
    );
  }

  factory SushiAssignment.stubPending({String reason = ''}) => SushiAssignment(
        apiBotUsername: '',
        pool: const [],
        providerId: 0,
        bindingToken: '',
        epoch: 0,
        pending: true,
        rawReply: reason,
      );

  /// Handles the client round-robins protocol DMs across (ADR 0011). Primary is included even
  /// when [pool] omitted it; empty names dropped. Order is pool order, then primary.
  List<String> get apiSendTargets {
    final seen = <String>{};
    final out = <String>[];
    void add(String raw) {
      final name = raw.trim();
      if (name.isEmpty) return;
      if (seen.add(name.toLowerCase())) out.add(name);
    }

    for (final name in pool) {
      add(name);
    }
    add(apiBotUsername);
    return out;
  }

  /// True when init-bot refused this person because the app is not open to the public.
  /// Reads `Err.code` (field 1, varint), which is the first thing the server writes.
  bool get notPublic {
    if (!isError || payloadBase64.isEmpty) return false;
    try {
      final bytes = base64Url.decode(base64Url.normalize(payloadBase64));
      return bytes.length >= 2 && bytes[0] == 0x08 && bytes[1] == errCodeNotPublic;
    } on FormatException {
      return false;
    }
  }

  /// True when protocol DMs have a send target (docs/02 §1).
  bool get usable => !pending && apiSendTargets.isNotEmpty;
}

/// Keep a live assignment when `/initbot` returns ERR/pending. Saving that pending
/// blob used to wipe catalog (`_bindSession` empty owner) and skip `/home`.
SushiAssignment sushiCoalesceAssignment(SushiAssignment incoming, SushiAssignment? previous) {
  if (incoming.usable) return incoming;
  if (previous != null && previous.usable) return previous;
  return incoming;
}

int _apiBotCursor = 0;
bool _apiBotCursorSeeded = false;
final _apiBotRng = Random();

/// Reset the protocol-DM round-robin cursor. Pass `null` (default) to unseed so the next
/// [sushiNextApiBot] picks a random start; pass an int to pin the next pick for tests.
@visibleForTesting
void sushiResetApiBotCursor([int? value]) {
  if (value == null) {
    _apiBotCursorSeeded = false;
    _apiBotCursor = 0;
    return;
  }
  _apiBotCursor = value;
  _apiBotCursorSeeded = true;
}

/// Next API bot handle for a protocol DM (ADR 0011). Empty pool falls back to the primary.
String sushiNextApiBot(SushiAssignment assignment) {
  final bots = assignment.apiSendTargets;
  if (bots.isEmpty) return assignment.apiBotUsername;
  if (!_apiBotCursorSeeded) {
    _apiBotCursor = _apiBotRng.nextInt(bots.length);
    _apiBotCursorSeeded = true;
  }
  final bot = bots[_apiBotCursor % bots.length];
  _apiBotCursor++;
  return bot;
}

abstract final class SushiAssignmentStore {
  static const _prefsKey = 'sushi.assignment.v1';

  static Future<void> save(SushiAssignment assignment) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(assignment.toJson()));
  }

  static Future<SushiAssignment?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return SushiAssignment.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}

/// After TDLib Ready: do **not** POST `/auth/telegram`.
///
/// Sends `/initbot <corr>` to @[SushiConfig.initBotUsername], waits for `!` + base64url envelope,
/// decodes Assignment protobuf when type=15, persists result. Also clicks through main-bot's
/// onboarding first, since /initbot never creates a binding itself (docs/02 §1) — for a session
/// account, only that conversation does. Use this at login time; a bound session refreshing its
/// already-current Assignment should call [sushiRefreshInitbot] instead, which skips onboarding.
Future<SushiAssignment>? _runInitbotAfterReadyInFlight;

Future<SushiAssignment> sushiRunInitbotAfterTdlibReady() async {
  final inFlight = _runInitbotAfterReadyInFlight;
  if (inFlight != null) return inFlight;
  final future = _sushiRunInitbotAfterTdlibReadyBody();
  _runInitbotAfterReadyInFlight = future;
  try {
    return await future;
  } finally {
    if (identical(_runInitbotAfterReadyInFlight, future)) {
      _runInitbotAfterReadyInFlight = null;
    }
  }
}

Future<SushiAssignment> _sushiRunInitbotAfterTdlibReadyBody() async {
  assert(SushiConfig.isEnabled);

  final botSession = await SushiTdlibBridgeController.instance()
      .isNativeSessionActuallyBot();
  Object? onboardErr;
  if (!botSession) {
    try {
      await sushiEnsureMainBotOnboarded(
        username: SushiConfig.mainBotUsername,
        timeoutMs: 90000,
      );
    } catch (e, st) {
      debugPrint('[sushi] main-bot onboarding failed: $e\n$st');
      onboardErr = e;
    }
  }

  final assignment = await sushiRefreshInitbot();
  if (onboardErr != null &&
      (assignment.pending || assignment.apiSendTargets.isEmpty)) {
    throw StateError(
        'Could not finish Sushi setup in Telegram: $onboardErr');
  }
  return assignment;
}

/// Shown when the server is in testing mode and this person is not authorized (server ADR 0039).
String sushiNotPublicMessage({required bool fa}) => fa
    ? 'سوشی یک پروژهٔ آزمایشی و آموزشیه و برای استفادهٔ عمومی باز نیست. ثبت‌نام جدید بسته است.'
    : 'Sushi is a test and study project and is not open for public use. New registrations are closed.';

/// Phone/QR login must not enter Home with a pending assignment — leftover catalog
/// would then paint Play while `/play` skips.
void sushiEnsureAssignmentReady(SushiAssignment assignment) {
  if (assignment.usable) return;
  if (assignment.notPublic) throw StateError(sushiNotPublicMessage(fa: false));
  final blob = assignment.rawReply.toLowerCase();
  if (blob.contains('user_is_bot') || blob.contains("can't send messages to other bots")) {
    throw StateError(
      'Your bot cannot message Sushi bots yet. In @BotFather open the Mini App (or tap Open at the bottom), pick your bot, Bot Settings, and turn on Bot to Bot Communication Mode. Then tap Login again.',
    );
  }
  if (blob.contains('timeout')) {
    throw StateError(
      'Sushi timed out talking to Telegram. Check the network and try Login again.',
    );
  }
  throw StateError('Sushi is not ready yet. Finish setup in Telegram, then try again.');
}

/// Re-runs `/initbot` for an already-bound session, without touching main-bot: /initbot is
/// idempotent (docs/02 §1), so this just re-syncs the Assignment — the API bot pool and delivery
/// bot list it carries can both change server-side after the client last asked (docs/02 §7, docs/10
/// Q3). Called once per cold start and whenever a bound API bot stops answering (docs/02 §6-7), so
/// it deliberately never touches the human-visible main-bot chat the way a fresh login does.
Future<SushiAssignment> sushiRefreshInitbot() async {
  assert(SushiConfig.isEnabled);
  final corr = sushiNewCorrBase36();
  final cmd = '/initbot $corr';
  final bot = SushiConfig.initBotUsername;

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: bot,
      text: cmd,
      timeoutMs: 30000,
    );
    var parsed = sushiParseInitbotReply(reply, expectedCorrBase36: corr);
    debugPrint('[sushi] initbot reply type=${parsed.msgType} pending=${parsed.pending} len=${reply.length}');
    for (var attempt = 2; attempt <= 3 && !parsed.usable; attempt++) {
      debugPrint('[sushi] initbot retry $attempt after type=${parsed.msgType}');
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt - 1)));
      final corrN = sushiNewCorrBase36();
      final replyN = await sushiSendTextAndWaitReply(
        username: bot,
        text: '/initbot $corrN',
        timeoutMs: 30000,
      );
      parsed = sushiParseInitbotReply(replyN, expectedCorrBase36: corrN);
    }
    final assignment = sushiCoalesceAssignment(parsed, await SushiAssignmentStore.load());
    if (!parsed.usable && assignment.usable) {
      debugPrint('[sushi] initbot kept previous after type=${parsed.msgType}');
    }
    await SushiAssignmentStore.save(assignment);
    debugPrint(
      '[sushi] initbot ok pending=${assignment.pending} type=${assignment.msgType} '
      'apiBot=${assignment.apiBotUsername} epoch=${assignment.epoch} '
      'pool=${assignment.pool.length}',
    );

    // Keep every Sushi bot except main-bot out of the visible chat list — same start+mute+archive
    // treatment sushi already gives its delivery senders (SushiProviderBotsBootstrap).
    // main-bot is deliberately excluded: it's the one bot a person may actually want to open.
    //
    // The whole API pool is warmed so protocol DMs can round-robin (ADR 0011). Delivery bots ride
    // along too (docs/05 §6): deliveryd picks one per copy, and without a prior /start the first
    // play fails `400 chat not found`.
    if (!assignment.pending) {
      final apiBots = assignment.apiSendTargets;
      if (apiBots.isNotEmpty || assignment.deliveryBots.isNotEmpty) {
        unawaited(sushiEnsureProviderBotsReady([
          SushiTdlibProviderBot(id: 0, username: SushiConfig.initBotUsername),
          for (final username in apiBots)
            SushiTdlibProviderBot(id: 0, username: username),
          for (final username in assignment.deliveryBots)
            if (username.trim().isNotEmpty)
              SushiTdlibProviderBot(id: 0, username: username),
        ]));
      }
    }

    return assignment;
  } catch (e, st) {
    debugPrint('[sushi] initbot failed: $e\n$st');
    // Keep a working assignment. USER_IS_BOT (bot session DMing an API bot) used to overwrite
    // it with stubPending, after which home skipped fetch entirely ("no assignment yet").
    final previous = await SushiAssignmentStore.load();
    if (previous != null && previous.usable) {
      return previous;
    }
    final pending = SushiAssignment.stubPending(reason: e.toString());
    await SushiAssignmentStore.save(pending);
    return pending;
  }
}

bool _sushiColdStartInitbotDone = false;

/// Next dashboard mount must re-run `/initbot` (logout / account switch).
void sushiResetInitbotColdStart() {
  _sushiColdStartInitbotDone = false;
}

/// Fire-and-forget refresh, once per process: paints whatever is already cached immediately, then
/// quietly re-syncs in the background (docs/02 §7's cold-start half of bot rotation). Also arms the
/// reactive half here, once: after enough consecutive failures talking to the assigned API bot,
/// the bridge queue calls back into [sushiRefreshInitbot] on its own (docs/02 §6-7 — a bound bot
/// that has stopped answering).
void sushiRefreshInitbotOnColdStart({void Function()? onReady}) {
  if (_sushiColdStartInitbotDone) {
    onReady?.call();
    return;
  }
  _sushiColdStartInitbotDone = true;
  onRepeatedSendFailure = () {
    debugPrint('[sushi] repeated send failures — refreshing /initbot');
    unawaited(sushiRefreshInitbot());
  };
  unawaited(sushiRefreshInitbot().then((_) => onReady?.call()));
}

/// Parse `!` + base64url(envelope); decode Assignment protobuf when type == 15.
SushiAssignment sushiParseInitbotReply(String reply,
    {String? expectedCorrBase36}) {
  final SushiEnvelope env;
  try {
    env = SushiEnvelope.decode(reply);
  } catch (e) {
    return SushiAssignment.stubPending(reason: 'envelope decode failed: $e');
  }

  final isErr = env.type == SushiEnvelope.msgTypeErr;
  final isAssign = env.type == SushiEnvelope.msgTypeAssignment;
  final payloadB64 = base64Url.encode(env.payload);

  if (!isAssign) {
    return SushiAssignment(
      apiBotUsername: '',
      pool: const [],
      providerId: 0,
      bindingToken: '',
      epoch: 0,
      pending: true,
      msgType: env.type,
      corr: env.corr,
      rawReply: reply.trim(),
      payloadBase64: payloadB64,
      isError: isErr,
    );
  }

  try {
    final pb = SushiAssignmentPb.decode(env.payload);
    return SushiAssignment(
      apiBotUsername: pb.apiBotUsername,
      pool: pb.pool,
      providerId: pb.providerId,
      bindingToken: pb.bindingTokenBase64Url,
      epoch: pb.epoch,
      deliveryBots: pb.deliveryBots,
      pending: pb.apiBotUsername.isEmpty && pb.pool.isEmpty,
      msgType: env.type,
      corr: env.corr,
      rawReply: reply.trim(),
      payloadBase64: payloadB64,
      isError: false,
    );
  } catch (e) {
    return SushiAssignment(
      apiBotUsername: '',
      pool: const [],
      providerId: 0,
      bindingToken: '',
      epoch: 0,
      pending: true,
      msgType: env.type,
      corr: env.corr,
      rawReply: 'Assignment protobuf decode failed: $e',
      payloadBase64: payloadB64,
      isError: false,
    );
  }
}
