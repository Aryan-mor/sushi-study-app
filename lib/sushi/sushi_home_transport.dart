import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_app_platform.dart';
import 'package:fladder/sushi/sushi_app_update.dart';
import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_wire.dart';

/// Fetches one home tab from the Sushi API bot pool (docs/02 §3, docs/12 §2, ADR 0011).
///
/// Returns null on any failure — missing/pending assignment, a timed-out reply, an `ERR` reply, or
/// a malformed envelope. A failed fetch means empty rails on the dashboard, never a crash (mirrors
/// `sushiRunInitbotAfterTdlibReady`'s defensive style).
Future<SushiHomeRes?> sushiFetchHome({required int tab}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null ||
      assignment.pending ||
      assignment.apiSendTargets.isEmpty) {
    debugPrint('[sushi] home: no assignment yet, skipping fetch');
    return null;
  }

  final corr = sushiNewCorrBase36();
  final platform = await sushiAppPlatform();
  final requestText = sushiEncodeRequestText(
    'home',
    corr,
    sushiEncodeHomeReq(
      tab: tab,
      platform: platform,
      currentVersion: sushiUpdateCurrentVersion(),
    ),
  );

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: sushiNextApiBot(assignment),
      text: requestText,
      timeoutMs: 15000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr) {
      debugPrint('[sushi] home: server returned ERR (corr=${env.corr})');
      return null;
    }
    if (env.type != SushiEnvelope.msgTypeHomeRes) {
      debugPrint(
          '[sushi] home: unexpected msgType=${env.type} (corr=${env.corr})');
      return null;
    }
    final home = SushiHomeRes.decode(env.payload);
    await sushiNoteLatestApp(home.latestApp);
    sushiNotInterestedSink?.call(home.notInterested);
    return home;
  } catch (e, st) {
    debugPrint('[sushi] home fetch failed: $e\n$st');
    return null;
  }
}
