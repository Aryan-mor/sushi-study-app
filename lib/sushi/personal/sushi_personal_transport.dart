import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_wire.dart';

/// `sushi.v1.PersonalAction` (ADR 0038).
enum SushiPersonalAction {
  /// main-bot sends this person, on their Telegram account, a warning and the video's share link.
  share(1),

  /// Ends this person's access. The video and everyone else's access stay.
  delete(2);

  const SushiPersonalAction(this.wire);
  final int wire;
}

const _msgTypePersonalRes = 41;

/// Encodes `sushi.v1.PersonalReq`: field 1 `personal_id`, field 2 `action` (both varint).
Uint8List sushiEncodePersonalReq({required int personalId, required SushiPersonalAction action}) {
  final out = BytesBuilder();
  out.add(sushiUvarint((1 << 3) | 0));
  out.add(sushiUvarint(personalId));
  out.add(sushiUvarint((2 << 3) | 0));
  out.add(sushiUvarint(action.wire));
  return out.toBytes();
}

/// Sends the `personal` command. True when the server did it (delete) or queued it (share); false on
/// any failure, including no access. Never throws.
Future<bool> sushiPersonalAction({required int personalId, required SushiPersonalAction action}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null || assignment.pending || assignment.apiSendTargets.isEmpty) return false;
  final corr = sushiNewCorrBase36();
  final text = sushiEncodeRequestText(
    'personal',
    corr,
    sushiEncodePersonalReq(personalId: personalId, action: action),
  );
  try {
    final reply = await sushiSendTextAndWaitReply(
      username: sushiNextApiBot(assignment),
      text: text,
      timeoutMs: 15000,
      priority: true,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type != _msgTypePersonalRes) {
      debugPrint('[sushi] personal ${action.name}: unexpected type=${env.type}');
      return false;
    }
    return true;
  } catch (e) {
    debugPrint('[sushi] personal ${action.name} failed: $e');
    return false;
  }
}
