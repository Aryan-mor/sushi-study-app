import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_search_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

/// One committed catalog search (`/search`, docs/12 §6). Round-robins the API pool (ADR 0011).
///
/// Returns null on missing assignment, timeout, `ERR`, or a malformed envelope — same defensive
/// contract as [sushiFetchHome]. Debounce belongs to the caller (R-META-3).
Future<SushiSearchRes?> sushiFetchSearch(
    {required String query, int cursor = 0}) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return null;

  final assignment = await SushiAssignmentStore.load();
  if (assignment == null ||
      assignment.pending ||
      assignment.apiSendTargets.isEmpty) {
    debugPrint('[sushi] search: no assignment yet, skipping fetch');
    return null;
  }

  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText(
    'search',
    corr,
    sushiEncodeSearchReq(query: trimmed, cursor: cursor),
  );

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: sushiNextApiBot(assignment),
      text: requestText,
      timeoutMs: 15000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr) {
      debugPrint('[sushi] search: server returned ERR (corr=${env.corr})');
      return null;
    }
    if (env.type != SushiEnvelope.msgTypeSearchRes) {
      debugPrint(
          '[sushi] search: unexpected msgType=${env.type} (corr=${env.corr})');
      return null;
    }
    return SushiSearchRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] search fetch failed: $e\n$st');
    return null;
  }
}
