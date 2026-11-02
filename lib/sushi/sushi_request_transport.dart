import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_request_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

const _msgTypeRequestRes = 27;

/// Sends one content request (`/request`, ADR 0014 §D2): a wish for a movie or whole series we do
/// not carry yet. One message, one typed answer. Round-robins the API pool (ADR 0011).
///
/// Returns null on missing assignment, timeout, `ERR`, or a malformed envelope — the caller shows
/// a generic "try again" in that case. A real answer is always one of the [SushiRequestOutcome]s.
Future<SushiRequestRes?> sushiSendRequest({
  required int tmdbId,
  required int kind,
}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null ||
      assignment.pending ||
      assignment.apiSendTargets.isEmpty) {
    debugPrint('[sushi] request: no assignment yet, skipping');
    return null;
  }

  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText(
    'request',
    corr,
    sushiEncodeRequestReq(tmdbId: tmdbId, kind: kind),
  );

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: sushiNextApiBot(assignment),
      text: requestText,
      timeoutMs: 15000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr) {
      debugPrint('[sushi] request: server returned ERR (corr=${env.corr})');
      return null;
    }
    if (env.type != _msgTypeRequestRes) {
      debugPrint('[sushi] request: unexpected msgType=${env.type} (corr=${env.corr})');
      return null;
    }
    return SushiRequestRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] request failed: $e\n$st');
    return null;
  }
}
