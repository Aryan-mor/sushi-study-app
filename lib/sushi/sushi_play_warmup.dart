import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_play_pb.dart';
import 'package:fladder/sushi/sushi_play_transport.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

typedef SushiWarmupPlayFn = Future<SushiPlayRes?> Function({required int fileId, bool force});
typedef SushiWarmupArmFn = Future<void> Function(String locator);
typedef SushiWarmupAckFn = Future<void> Function({required int fileId, required int messageId});
typedef SushiWarmupPollFn = Future<SushiTdlibDeliveryRef?> Function(String locator);

/// Docs/05 §5: `/play` + ack, no playback session. Default Play-button file, or a newly picked
/// quality. Cached [SushiDelivered] lets the tap skip a second `/play` and go straight to
/// `getMessages`.
class SushiPlayWarmup {
  SushiPlayWarmup({
    SushiWarmupPlayFn play = sushiPlay,
    SushiWarmupArmFn arm = sushiArmDeliveryWaiter,
    SushiWarmupAckFn ack = sushiAck,
    SushiWarmupPollFn? poll,
  })  : _play = play,
        _arm = arm,
        _ack = ack,
        _poll = poll ?? _defaultPoll;

  final SushiWarmupPlayFn _play;
  final SushiWarmupArmFn _arm;
  final SushiWarmupAckFn _ack;
  final SushiWarmupPollFn _poll;

  final Map<int, SushiDelivered> _cache = {};
  final Map<int, Future<SushiDelivered?>> _inFlight = {};
  int? _pending;
  bool _paused = false;

  SushiDelivered? cached(int fileId) => _cache[fileId];

  void invalidate(int fileId) {
    _cache.remove(fileId);
  }

  /// Docs/05 §5: never start warmup on a backgrounded device. In-flight `/play` still finishes.
  void pause() {
    _paused = true;
  }

  void resume() {
    _paused = false;
    final id = _pending;
    _pending = null;
    if (id != null) schedule(id);
  }

  void clear() {
    _cache.clear();
    _inFlight.clear();
    _pending = null;
  }

  void schedule(int? fileId) {
    
    if (fileId == null || fileId <= 0) return;
    if (_cache.containsKey(fileId) || _inFlight.containsKey(fileId)) return;
    if (_paused) {
      _pending = fileId;
      return;
    }
    final run = _run(fileId);
    _inFlight[fileId] = run;
    unawaited(run.whenComplete(() => _inFlight.remove(fileId)));
  }

  void scheduleFromStreams(MediaStreamsModel? streams) {
    schedule(sushiFileIdFromVersionStreamId(streams?.currentVersionStream?.id));
  }

  Future<SushiDelivered?> wait(int fileId) async {
    final hit = _cache[fileId];
    if (hit != null) return hit;
    return _inFlight[fileId];
  }

  Future<SushiDelivered?> _run(int fileId) async {
    final locator = sushiLocatorForFile(fileId);
    debugPrint('[sushi] play warmup fileId=$fileId');
    await _arm(locator);
    final playRes = await _play(fileId: fileId, force: false);
    if (playRes == null) return null;

    var delivered = playRes.delivered;
    if (delivered == null || delivered.messageId <= 0) {
      final ref = await _poll(locator);
      if (ref != null && ref.messageId > 0 && ref.providerBotId > 0) {
        delivered = SushiDelivered(
          botId: ref.providerBotId,
          messageId: ref.messageId,
          locator: locator,
        );
      }
    }
    if (delivered == null || delivered.messageId <= 0) {
      debugPrint('[sushi] play warmup pending timeout fileId=$fileId');
      return null;
    }
    unawaited(_ack(fileId: fileId, messageId: delivered.messageId));
    _cache[fileId] = delivered;
    debugPrint(
      '[sushi] play warmup ready fileId=$fileId botId=${delivered.botId} messageId=${delivered.messageId}',
    );
    return delivered;
  }
}

Future<SushiTdlibDeliveryRef?> _defaultPoll(String locator) async {
  const timeout = Duration(seconds: 15);
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final ref = await sushiDeliveryRefForLocator(locator);
    if (ref != null && ref.messageId > 0 && ref.providerBotId > 0) return ref;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return sushiDeliveryRefForLocator(locator);
}

final sushiPlayWarmup = SushiPlayWarmup();
