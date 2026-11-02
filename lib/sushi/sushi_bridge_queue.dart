import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_bridge_file.dart';

import 'package:fladder/sushi/sushi_tdlib_bridge_controller.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

/// Serializes every Sushi-initiated call into the native TDLib bridge (home, initbot, item, files,
/// main-bot onboarding, bot archiving, ...) behind one queue, so at most one is ever in flight at a
/// time.
///
/// This exists for two reasons at once: it's the "one message per second" outbound scheduler
/// docs/11 §4 already calls for (never built, but the constraint is real regardless), and — found
/// the hard way, live on a real phone — running two of these calls concurrently (e.g. a dashboard
/// home refresh overlapping a detail screen's item fetch) crashes the whole process with a native
/// Go runtime fault (`fatal error: bulkBarrierPreWrite: unaligned arguments`), reproduced on both
/// an x86_64 emulator and an arm64 device. gomobile's generated JNI bridge is not safe to enter from
/// two threads at once for this client, so nothing may call it without going through here.
///
/// Two lanes, not two threads: the JNI single-entry rule above is unchanged — exactly one call runs
/// at a time. [priority] only reorders what runs *next* when the current call finishes. The
/// playback path (arm waiter → /play → startPlaybackSession → deliveryRef polling) takes the fast
/// lane so a slow or dead API bot answering an unrelated /item can no longer sit in front of a
/// user's tap for its full reply timeout (device log 2026-09-01: a 25s /item timeout delayed a
/// play warmup by ~14s).
final Queue<_QueuedCall> _highQueue = Queue<_QueuedCall>();
final Queue<_QueuedCall> _normalQueue = Queue<_QueuedCall>();
bool _draining = false;

class _QueuedCall {
  _QueuedCall(this.run);

  /// Runs the wrapped call and settles its caller's completer; never throws (errors are forwarded
  /// through the completer), so the drain loop can simply await it and move on.
  final Future<void> Function() run;
}

Future<T> _enqueue<T>(Future<T> Function() call, {bool priority = false}) {
  final completer = Completer<T>();
  Future<void> run() async {
    try {
      completer.complete(await call());
    } catch (e, st) {
      completer.completeError(e, st);
    }
  }

  (priority ? _highQueue : _normalQueue).add(_QueuedCall(run));
  _drain();
  return completer.future;
}

void _drain() {
  if (_draining) return;
  _draining = true;
  Future<void>(() async {
    while (_highQueue.isNotEmpty || _normalQueue.isNotEmpty) {
      final next = _highQueue.isNotEmpty ? _highQueue.removeFirst() : _normalQueue.removeFirst();
      await next.run();
    }
    _draining = false;
  });
}

/// Set by sushi_initbot_transport.dart. Fired after enough consecutive [sushiSendTextAndWaitReply]
/// failures in a row that the API pool looks dead, not just having one bad moment (docs/02
/// §6-7) — the reactive half of bot rotation, whose cold-start half is
/// sushiRefreshInitbotOnColdStart. A queue with nobody listening (this field left null) just logs
/// failures and moves on, same as before this existed.
void Function()? onRepeatedSendFailure;

/// How many sendTextAndWaitReply calls in a row must fail before [onRepeatedSendFailure] fires.
/// Not 1: a single timeout is routine (docs/02 §6 already retries within one request), this is for
/// "the bot really has stopped answering".
const _repeatedFailureThreshold = 2;
int _consecutiveSendFailures = 0;

/// Total [sushiSendTextAndWaitReply] calls since launch (or the last [sushiResetRequestCounter]) —
/// every Sushi wire command funnels through this one function, so this is a single, reliable place
/// to catch "over-requesting our bots" regressions without adding logging at every call site. Read
/// by the Sushi e2e suite (integration_test/sushi_e2e_test.dart); harmless in production.
int sushiRequestCount = 0;

void sushiResetRequestCounter() => sushiRequestCount = 0;

Future<String> sushiSendTextAndWaitReply({
  required String username,
  required String text,
  required int timeoutMs,
  bool priority = false,
}) async {
  final controller = SushiTdlibBridgeController.instance();
  sushiRequestCount++;
  final cmd = text.startsWith('/') ? text.split(' ').first : 'text';
  debugPrint('[sushi] send start cmd=$cmd bot=$username timeoutMs=$timeoutMs');
  try {
    final reply = await _enqueue(
      () => controller.sendTextAndWaitReply(
          username: username, text: text, timeoutMs: timeoutMs),
      priority: priority,
    );
    _consecutiveSendFailures = 0;
    return reply;
  } catch (e) {
    final msg = e.toString();
    // Bot-to-bot is a session-identity problem, not a dead API bot. Refreshing /initbot here
    // wiped a good assignment and left home empty.
    if (msg.contains('USER_IS_BOT')) {
      debugPrint(
          '[sushi] send failed USER_IS_BOT — bot session used MTProto sendMessage; Bot API token missing');
      rethrow;
    }
    _consecutiveSendFailures++;
    if (_consecutiveSendFailures >= _repeatedFailureThreshold) {
      _consecutiveSendFailures = 0;
      onRepeatedSendFailure?.call();
    }
    rethrow;
  }
}

/// Sends [text] to [username] without waiting for a reply (Sushi `/ack`, future watch-progress
/// reports). Still routed through the same queue as every other Sushi call — the underlying native
/// call crosses into the same gomobile client, so it must stay serialized against them — but it
/// resolves as soon as the send completes, never blocking on a reply that is not coming. Counted in
/// [sushiRequestCount] like every other wire call.
Future<void> sushiSendTextFireAndForget(
    {required String username, required String text, bool priority = false}) {
  final controller = SushiTdlibBridgeController.instance();
  sushiRequestCount++;
  return _enqueue(
      () => controller.sendTextFireAndForget(username: username, text: text),
      priority: priority);
}

Future<void> sushiEnsureMainBotOnboarded(
    {required String username, required int timeoutMs}) {
  final controller = SushiTdlibBridgeController.instance();
  return _enqueue(
    () => controller.ensureMainBotOnboarded(
        username: username, timeoutMs: timeoutMs),
  );
}

Future<bool> sushiEnsureProviderBotsReady(List<SushiTdlibProviderBot> bots) {
  final controller = SushiTdlibBridgeController.instance();
  return _enqueue(() => controller.ensureProviderBotsReady(bots));
}

// The playback path runs in the fast lane (see [_enqueue] doc): a user waiting on a tap must not
// queue behind background /home or /item traffic.
Future<void> sushiArmDeliveryWaiter(String locator) {
  final controller = SushiTdlibBridgeController.instance();
  return _enqueue(() => controller.armDeliveryWaiter(locator), priority: true);
}

Future<String> sushiStartPlaybackSession(SushiTdlibPlaybackSource source) {
  final controller = SushiTdlibBridgeController.instance();
  return _enqueue(() => controller.startPlaybackSession(source), priority: true);
}

Future<void> sushiStopPlaybackSession(String sessionUri) {
  if (sessionUri.isEmpty) return Future.value();
  final controller = SushiTdlibBridgeController.instance();
  return _enqueue(() => controller.stopPlaybackSession(sessionUri));
}

Future<SushiTdlibDeliveryRef?> sushiDeliveryRefForLocator(String locator) {
  final controller = SushiTdlibBridgeController.instance();
  return _enqueue(() => controller.deliveryRefForLocator(locator), priority: true);
}

/// Personal video thumbnail (ADR 0037 §6). Same gomobile JNI as playback, so it goes through the
/// queue; normal lane, because nobody is waiting on it.
Future<void> sushiFetchDocumentThumb({
  required int messageId,
  required String locator,
  required String outPath,
}) {
  final controller = SushiTdlibBridgeController.instance();
  return _enqueue(
    () => controller.fetchDocumentThumb(messageId: messageId, locator: locator, outPath: outPath),
  );
}

/// Subtitle document download (doc 15 §7). Same gomobile JNI as playback — must not overlap
/// `startPlaybackSession` / protocol calls on a second Dart isolate. Fast lane so a hop-to-next
/// episode's play is not stuck behind `/home`.
///
/// The bridge returns a filesystem path. Subtitle bytes stay out of the gomobile string
/// return. [sushiReadBridgeFile] reads the file and deletes it.
Future<String> sushiFetchSmallDocument({
  required int botId,
  required int messageId,
  required String locator,
  int timeoutMs = 30000,
}) async {
  final controller = SushiTdlibBridgeController.instance();
  final path = await _enqueue(
    () => controller.fetchSmallDocument(
      botId: botId,
      messageId: messageId,
      locator: locator,
      timeoutMs: timeoutMs,
    ),
    priority: true,
  );
  return sushiReadBridgeFile(path);
}
