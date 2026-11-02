import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_tdlib_playback_resolver.dart'
    show sushiIsTelegramDeliveryWaitTimeoutError, sushiIsTdlibFileMissingError;
import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/personal/sushi_personal_thumbs.dart';
import 'package:fladder/sushi/sushi_play_pb.dart';
import 'package:fladder/sushi/sushi_play_transport.dart';
import 'package:fladder/sushi/sushi_play_warmup.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

const _sushiPlayLogTag = 'SUSHI_SUSHI';
void _log(String message) => debugPrint('$_sushiPlayLogTag: $message');

/// Resolves one Sushi file id to a playable url, following docs/05-media-delivery.md §4:
///
/// 1. Arm the delivery-bot waiter for this file's locator BEFORE asking (a push that arrives
///    before the waiter exists is lost forever for a bot-login client).
/// 2. Send `/play`. A `Delivered` answer names a remembered message (no copy needed); a `Pending`
///    answer means deliveryd is copying it now — the native `startPlaybackSession(0/0, locator)`
///    already knows how to wait on the armed locator waiter for that copy to land (the same
///    primitive `sushi_tdlib_playback_resolver.dart` uses for its own cold plays).
/// 3. A remembered message that turns out to be gone (deleted, wrong chat, cleared history) is a
///    "broken row" (docs/05 §4/§6): retry once with `force: true`, which makes the server delete
///    the row and re-deliver under the same locator — the waiter armed in step 1 is still good.
///
/// A personal video (ADR 0037) passes [personalId] instead of a file id (pass 0 for [fileId]). It
/// takes the same path under its own locator (`plp_<id>`), with no warmup, and caches the
/// document's thumbnail once the delivered message is known (ADR 0037 §6).
Future<String> sushiResolvePlaybackUrl({
  required int fileId,
  int personalId = 0,
  bool preferHttpBridge = false,
  int mode = sushiModeStream,
}) async {
  final sw = Stopwatch()..start();
  try {
    final url = await _resolvePlaybackUrl(
      fileId: fileId,
      personalId: personalId,
      preferHttpBridge: preferHttpBridge,
      mode: mode,
      sw: sw,
    );
    _log('resolve OK fileId=$fileId totalMs=${sw.elapsedMilliseconds} url=$url');
    return url;
  } catch (e) {
    _log('resolve FAILED fileId=$fileId totalMs=${sw.elapsedMilliseconds} error=$e');
    rethrow;
  }
}

Future<String> _resolvePlaybackUrl({
  required int fileId,
  required int personalId,
  required bool preferHttpBridge,
  required int mode,
  required Stopwatch sw,
}) async {
  final locator = personalId > 0 ? sushiLocatorForPersonal(personalId) : sushiLocatorForFile(fileId);
  // No warmup for a personal video: nothing is copied until the user presses play (ADR 0037 §4).
  final warmed = personalId > 0 ? null : await sushiPlayWarmup.wait(fileId);
  _log('resolve fileId=$fileId warmed=${warmed != null && warmed.messageId > 0} '
      'warmupWaitMs=${sw.elapsedMilliseconds}');
  if (warmed != null && warmed.messageId > 0) {
    await sushiArmDeliveryWaiter(locator);
    try {
      return await _startSession(
        fileId: fileId,
        personalId: personalId,
        locator: locator,
        playRes: SushiPlayRes(delivered: warmed),
        preferHttpBridge: preferHttpBridge,
        mode: mode,
      );
    } catch (e) {
      sushiPlayWarmup.invalidate(fileId);
      _log('warmup delivery unusable fileId=$fileId error=$e — falling through to /play');
    }
  }

  await sushiArmDeliveryWaiter(locator);

  final playRes = await sushiPlay(fileId: fileId, personalId: personalId, mode: mode);
  if (playRes == null) {
    throw StateError('sushi play: no reply for ${personalId > 0 ? 'personal video $personalId' : 'file $fileId'}');
  }

  return _startSession(
    fileId: fileId,
    personalId: personalId,
    locator: locator,
    playRes: playRes,
    preferHttpBridge: preferHttpBridge,
    mode: mode,
  );
}

/// Polls [sushiDeliveryRefForLocator] (queued, so this never races the native side's own use of
/// the bridge) until the push lands or [timeout] elapses. Mirrors
/// `sushi_tdlib_playback_resolver.dart`'s `waitForTdlibDeliveryRef`, but through the Sushi
/// queue rather than calling the controller directly.
Future<SushiTdlibDeliveryRef?> _pollDeliveryRef(
  String locator, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final ref = await sushiDeliveryRefForLocator(locator);
    if (ref != null && ref.messageId > 0 && ref.providerBotId > 0) {
      return ref;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return sushiDeliveryRefForLocator(locator);
}

SushiDelivered? _deliveredFromSessionRef(SushiTdlibDeliveryRef? ref, String locator) {
  if (ref == null || ref.messageId <= 0 || ref.providerBotId <= 0) return null;
  return SushiDelivered(botId: ref.providerBotId, messageId: ref.messageId, locator: locator);
}

Future<String> _startSession({
  required int fileId,
  int personalId = 0,
  required String locator,
  required SushiPlayRes playRes,
  required bool preferHttpBridge,
  int mode = sushiModeStream,
  bool isRetry = false,
}) async {
  var delivered = playRes.delivered;
  // copyMessage's message_id is the *sender* numbering. Bot-login TDLib uses the receiver's.
  // A push that landed while /play was in flight is already in DeliveryRef — use that, don't 0/0.
  final sessionRef = _deliveredFromSessionRef(await sushiDeliveryRefForLocator(locator), locator);
  if (delivered == null || delivered.messageId == 0) {
    delivered = sessionRef ?? delivered;
  }

  // A /play reply's `botId` is the backend's provider-bot table id (e.g. 5), NOT the Telegram
  // user id of the DM sender that the native resolver's guard checks against
  // (resolveVideoFileByDMMessageID: `senderID != providerBotID` -> OX_DM_STALE). Passing it made
  // every warm play fail — "dm message 1180 came from bot 8271796073, expected 5" (device log
  // 2026-09-01) — and pay a full re-copy each time. Only a locally recorded DeliveryRef carries
  // the real sender id; trust the bot id only when that ref confirms this exact message,
  // otherwise send 0 and let native learn it from the message (`if providerBotID <= 0 {
  // providerBotID = senderID }`).
  final trustedBotId = (sessionRef != null &&
          sessionRef.messageId > 0 &&
          sessionRef.messageId == delivered?.messageId)
      ? sessionRef.botId
      : 0;

  final source = SushiTdlibPlaybackSource(
    providerBotId: trustedBotId,
    messageId: delivered?.messageId ?? 0,
    preferHttpBridge: preferHttpBridge,
    locator: locator,
  );

  _log(
    'startPlaybackSession fileId=$fileId providerBotId=${source.providerBotId} '
    'serverBotId=${delivered?.botId ?? 0} messageId=${source.messageId} '
    'pending=${delivered == null} locator=$locator',
  );

  try {
    final session = await sushiStartPlaybackSession(source);
    _log('startPlaybackSession ok -> $session');
    final landedMessageId = delivered?.messageId ?? (await sushiDeliveryRefForLocator(locator))?.messageId;
    if (landedMessageId != null && landedMessageId > 0) {
      unawaited(sushiAck(fileId: fileId, personalId: personalId, messageId: landedMessageId));
      if (personalId > 0) {
        // The card's thumbnail comes from this very message (ADR 0037 §6): fetched once, cached.
        unawaited(sushiCachePersonalThumb(personalId: personalId, messageId: landedMessageId, locator: locator));
      }
    }
    return session;
  } catch (e) {
    _log('startPlaybackSession FAILED fileId=$fileId error=$e');

    if (sushiIsTelegramDeliveryWaitTimeoutError(e)) {
      final landed = await _pollDeliveryRef(locator);
      if (landed != null && landed.messageId > 0 && landed.providerBotId > 0) {
        _log('retry after 0/0 timeout using landed botId=${landed.providerBotId} messageId=${landed.messageId}');
        return _startSession(
          fileId: fileId,
          personalId: personalId,
          locator: locator,
          playRes: SushiPlayRes(delivered: _deliveredFromSessionRef(landed, locator)),
          preferHttpBridge: preferHttpBridge,
          mode: mode,
          isRetry: true,
        );
      }
      rethrow;
    }

    if (isRetry) rethrow;

    if (delivered != null && sushiIsTdlibFileMissingError(e)) {
      final sessionRef = _deliveredFromSessionRef(await sushiDeliveryRefForLocator(locator), locator);
      if (sessionRef != null && sessionRef.messageId != delivered.messageId) {
        _log('stale server id ${delivered.messageId}; using session ref ${sessionRef.messageId}');
        return _startSession(
          fileId: fileId,
          personalId: personalId,
          locator: locator,
          playRes: SushiPlayRes(delivered: sessionRef),
          preferHttpBridge: preferHttpBridge,
          mode: mode,
          isRetry: true,
        );
      }
      _log('delivery stale for $locator — forcing re-delivery');
      sushiPlayWarmup.invalidate(fileId);
      final forced = await sushiPlay(fileId: fileId, personalId: personalId, force: true, mode: mode);
      if (forced != null) {
        return _startSession(
          fileId: fileId,
          personalId: personalId,
          locator: locator,
          playRes: forced,
          preferHttpBridge: preferHttpBridge,
          mode: mode,
          isRetry: true,
        );
      }
    }

    rethrow;
  }
}
