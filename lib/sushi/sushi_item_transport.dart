import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

const _msgTypeItemRes = 4;
const _msgTypeFilesRes = 6;

/// Fetches one title page — overview, extras, and a thin season index (docs/12 §4, ADR 0028).
/// Round-robins the API pool (ADR 0011). Returns null on any failure (never throws): a title
/// page with no extra detail yet is a normal, recoverable state, not different from the home
/// rails' own defensive style.
Future<SushiItemRes?> sushiFetchItem(
    {required int tmdbId, required int kind}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null ||
      assignment.pending ||
      assignment.apiSendTargets.isEmpty) {
    debugPrint('[sushi] item: no assignment yet, skipping fetch');
    return null;
  }

  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText(
      'item', corr, sushiEncodeItemReq(tmdbId: tmdbId, kind: kind));

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: sushiNextApiBot(assignment),
      text: requestText,
      // 10s, not 25s: a healthy /item answers in well under a second (device log 2026-09-01), so a
      // long ceiling here only means a dead API bot ties up its queue slot — and counts toward
      // rotation — that much slower. The playback path no longer waits behind this (fast lane), but
      // detail screens still should not hang 25s on a bad bot.
      timeoutMs: 10000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr) {
      debugPrint(
          '[sushi] item: server returned ERR tmdbId=$tmdbId kind=$kind corr=${env.corr}');
      return null;
    }
    if (env.type != _msgTypeItemRes) {
      debugPrint(
          '[sushi] item: unexpected msgType=${env.type} tmdbId=$tmdbId kind=$kind corr=${env.corr}');
      return null;
    }
    return SushiItemRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] item fetch failed: $e\n$st');
    return null;
  }
}

/// Fetches one episode's pick-list (docs/12 §5) — a movie asks this on its single episode
/// directly; a series page would ask it once an episode is picked. 5-minute TTL is the caller's
/// responsibility (this always goes to the network).
Future<SushiFilesRes?> sushiFetchFiles({required int episodeId}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null ||
      assignment.pending ||
      assignment.apiSendTargets.isEmpty) {
    debugPrint('[sushi] files: no assignment yet, skipping fetch');
    return null;
  }

  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText(
      'files', corr, sushiEncodeFilesReq(episodeId: episodeId));

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: sushiNextApiBot(assignment),
      text: requestText,
      timeoutMs: 15000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr) {
      debugPrint('[sushi] files: server returned ERR (corr=${env.corr})');
      return null;
    }
    if (env.type != _msgTypeFilesRes) {
      debugPrint(
          '[sushi] files: unexpected msgType=${env.type} (corr=${env.corr})');
      return null;
    }
    return SushiFilesRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] files fetch failed: $e\n$st');
    return null;
  }
}

Future<SushiEpisodesRes?> sushiFetchEpisodes({
  required int tmdbId,
  required int kind,
  required int seasonNo,
  int page = 0,
}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null ||
      assignment.pending ||
      assignment.apiSendTargets.isEmpty) {
    debugPrint('[sushi] episodes: no assignment yet, skipping fetch');
    return null;
  }

  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText(
    'episodes',
    corr,
    sushiEncodeEpisodesReq(tmdbId: tmdbId, kind: kind, seasonNo: seasonNo, page: page),
  );

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: sushiNextApiBot(assignment),
      text: requestText,
      timeoutMs: 10000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr) {
      debugPrint(
          '[sushi] episodes: server returned ERR tmdbId=$tmdbId season=$seasonNo corr=${env.corr}');
      return null;
    }
    if (env.type != SushiEnvelope.msgTypeEpisodesRes) {
      debugPrint(
          '[sushi] episodes: unexpected msgType=${env.type} tmdbId=$tmdbId season=$seasonNo');
      return null;
    }
    return SushiEpisodesRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] episodes fetch failed: $e\n$st');
    return null;
  }
}
