import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_sync_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

const _msgTypeSyncRes = 12;

/// Cross-device watched-state delta (docs/11 §6.1). Returns null on any failure (never throws) —
/// same defensive style as the other fetchers; the caller just tries again next launch.
Future<SushiSyncRes?> sushiFetchSync({required int watchedWatermark}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null ||
      assignment.pending ||
      assignment.apiSendTargets.isEmpty) {
    debugPrint('[sushi] sync: no assignment yet, skipping fetch');
    return null;
  }

  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText(
      'sync', corr, sushiEncodeSyncReq(watchedWatermark: watchedWatermark));

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: sushiNextApiBot(assignment),
      text: requestText,
      timeoutMs: 15000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr) {
      debugPrint('[sushi] sync: server returned ERR (corr=${env.corr})');
      return null;
    }
    if (env.type != _msgTypeSyncRes) {
      debugPrint('[sushi] sync: unexpected msgType=${env.type} (corr=${env.corr})');
      return null;
    }
    return SushiSyncRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] sync fetch failed: $e\n$st');
    return null;
  }
}
