import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_app_platform.dart';
import 'package:fladder/sushi/sushi_app_update_pb.dart';
import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_wire.dart';

const sushiMsgTypeAppUpdateRes = 31;

/// Asks the API bot to copy the latest binary into the protocol chat (ADR 0019).
Future<SushiAppUpdateRes?> sushiFetchAppUpdate({String? platform}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null ||
      assignment.pending ||
      assignment.apiSendTargets.isEmpty) {
    debugPrint('[sushi] appupdate: no assignment yet, skipping');
    return null;
  }

  final plat = platform ?? await sushiAppPlatform();
  if (plat.isEmpty) {
    debugPrint('[sushi] appupdate: unknown platform');
    return null;
  }

  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText(
    'appupdate',
    corr,
    sushiEncodeAppUpdateReq(platform: plat),
  );

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: sushiNextApiBot(assignment),
      text: requestText,
      timeoutMs: 20000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr) {
      debugPrint('[sushi] appupdate: server returned ERR (corr=${env.corr})');
      return null;
    }
    if (env.type != sushiMsgTypeAppUpdateRes) {
      debugPrint('[sushi] appupdate: unexpected msgType=${env.type}');
      return null;
    }
    return SushiAppUpdateRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] appupdate failed: $e\n$st');
    return null;
  }
}
