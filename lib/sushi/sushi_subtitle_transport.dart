import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_subtitle_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

/// Subtitle search (`/subtitle`, doc 15 §7) — server-proxied, so the provider (subdl) API key
/// never reaches the client. Round-robins the API pool (ADR 0011).
///
/// Returns null on missing assignment, timeout, `ERR`, or a malformed envelope — same defensive
/// contract as [sushiFetchSearch].
Future<SushiSubtitleRes?> sushiFetchSubtitles({
  required int tmdbId,
  required int kind,
  int seasonNo = 0,
  int episodeNo = 0,
  String lang = '',
  int durationMin = 0,
  String sourceLabel = '',
}) async {
  if (tmdbId == 0) return null;

  final assignment = await SushiAssignmentStore.load();
  if (assignment == null || assignment.pending || assignment.apiSendTargets.isEmpty) {
    debugPrint('[sushi] subtitle: no assignment yet, skipping fetch');
    return null;
  }

  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText(
    'subtitle',
    corr,
    sushiEncodeSubtitleReq(
      tmdbId: tmdbId,
      kind: kind,
      seasonNo: seasonNo,
      episodeNo: episodeNo,
      lang: lang,
      durationMin: durationMin,
      sourceLabel: sourceLabel,
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
      debugPrint('[sushi] subtitle: server returned ERR (corr=${env.corr})');
      return null;
    }
    if (env.type != SushiEnvelope.msgTypeSubtitleRes) {
      debugPrint('[sushi] subtitle: unexpected msgType=${env.type} (corr=${env.corr})');
      return null;
    }
    return SushiSubtitleRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] subtitle fetch failed: $e\n$st');
    return null;
  }
}

/// Resolves one chosen pack's [tag] (opaque, from a prior [sushiFetchSubtitles] pack) to its
/// actual subtitle text (`/subtitle_file`).
Future<SushiSubtitleFileRes?> sushiFetchSubtitleFile({required String tag}) async {
  if (tag.isEmpty) return null;

  final assignment = await SushiAssignmentStore.load();
  if (assignment == null || assignment.pending || assignment.apiSendTargets.isEmpty) {
    debugPrint('[sushi] subtitle_file: no assignment yet, skipping fetch');
    return null;
  }

  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText(
    'subtitle_file',
    corr,
    sushiEncodeSubtitleFileReq(tag: tag),
  );

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: sushiNextApiBot(assignment),
      text: requestText,
      timeoutMs: 20000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr) {
      debugPrint('[sushi] subtitle_file: server returned ERR (corr=${env.corr})');
      return null;
    }
    if (env.type != SushiEnvelope.msgTypeSubtitleFileRes) {
      debugPrint('[sushi] subtitle_file: unexpected msgType=${env.type} (corr=${env.corr})');
      return null;
    }
    return SushiSubtitleFileRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] subtitle_file fetch failed: $e\n$st');
    return null;
  }
}
