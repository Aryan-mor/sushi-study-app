import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_list_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

const _msgTypePersonRes = 23;
const _msgTypeListRes = 25;

Future<SushiPersonRes?> sushiFetchPerson({required int tmdbId}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null ||
      assignment.pending ||
      assignment.apiSendTargets.isEmpty) {
    return null;
  }
  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText(
      'person', corr, sushiEncodePersonReq(tmdbId: tmdbId));
  try {
    final reply = await sushiSendTextAndWaitReply(
      username: sushiNextApiBot(assignment),
      text: requestText,
      timeoutMs: 25000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr || env.type != _msgTypePersonRes) {
      debugPrint('[sushi] person: unexpected type=${env.type} tmdbId=$tmdbId');
      return null;
    }
    return SushiPersonRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] person fetch failed: $e\n$st');
    return null;
  }
}

Future<SushiListRes?> sushiFetchList({
  required SushiListScope scope,
  SushiListSort sort = SushiListSort.name,
  bool sortDesc = false,
  String genre = '',
  int year = 0,
  String q = '',
  int cursor = 0,
  int playlistId = 0,
  int collectionId = 0,
}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null ||
      assignment.pending ||
      assignment.apiSendTargets.isEmpty) {
    return null;
  }
  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText(
    'list',
    corr,
    sushiEncodeListReq(
      scope: scope,
      sort: sort,
      sortDesc: sortDesc,
      genre: genre,
      year: year,
      q: q,
      cursor: cursor,
      playlistId: playlistId,
      collectionId: collectionId,
    ),
  );
  try {
    final reply = await sushiSendTextAndWaitReply(
      username: sushiNextApiBot(assignment),
      text: requestText,
      timeoutMs: 15000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr || env.type != _msgTypeListRes) {
      debugPrint('[sushi] list: unexpected type=${env.type}');
      return null;
    }
    return SushiListRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] list fetch failed: $e\n$st');
    return null;
  }
}

/// Fire-and-forget fav / later / follow (docs/11, ADR 0014 §D3).
Future<void> sushiSendFavEvent(
    {required int tmdbId, required int kind, required bool on}) async {
  await _sendEvent(eventField: 1, inner: _flagInner(tmdbId: tmdbId, kind: kind, on: on));
}

Future<void> sushiSendLaterEvent(
    {required int tmdbId, required int kind, required bool on}) async {
  await _sendEvent(eventField: 2, inner: _flagInner(tmdbId: tmdbId, kind: kind, on: on));
}

/// NotInterestedEvent — same body as fav / later. Field 6 on Event.
Future<void> sushiSendNotInterestedEvent(
    {required int tmdbId, required int kind, required bool on}) async {
  await _sendEvent(eventField: 6, inner: _flagInner(tmdbId: tmdbId, kind: kind, on: on));
}

/// FollowEvent { tmdb_id = 1; bool on = 2; } — series-only, so no kind field (ADR 0014 §D3).
Future<void> sushiSendFollowEvent({required int tmdbId, required bool on}) async {
  final inner = BytesBuilder();
  _writeTag(inner, 1, 0);
  inner.add(sushiUvarint(tmdbId));
  if (on) {
    _writeTag(inner, 2, 0);
    inner.add(sushiUvarint(1));
  }
  await _sendEvent(eventField: 3, inner: inner.toBytes());
}

/// ProgEvent { episode_id = 1; position_s = 2; file_id = 3; duration_s = 4; personal_id = 5; }
/// — fire-and-forget. A personal video (ADR 0037) sends [personalId] and no episode id.
Future<void> sushiSendProgEvent({
  required int episodeId,
  required int positionS,
  int fileId = 0,
  int durationS = 0,
  int personalId = 0,
}) async {
  if (episodeId <= 0 && personalId <= 0) return;
  await _sendEvent(
    eventField: 4,
    inner: sushiEncodeProgEvent(
      episodeId: episodeId,
      positionS: positionS,
      fileId: fileId,
      durationS: durationS,
      personalId: personalId,
    ),
  );
}

/// The `ProgEvent` body, fields in number order. A personal video (ADR 0037) carries
/// `personal_id` and no `episode_id` — the two id spaces overlap, so never both.
Uint8List sushiEncodeProgEvent({
  required int episodeId,
  required int positionS,
  int fileId = 0,
  int durationS = 0,
  int personalId = 0,
}) {
  final inner = BytesBuilder();
  if (personalId <= 0 && episodeId > 0) {
    _writeTag(inner, 1, 0);
    inner.add(sushiUvarint(episodeId));
  }
  if (positionS != 0) {
    _writeTag(inner, 2, 0);
    inner.add(sushiUvarint(positionS < 0 ? 0 : positionS));
  }
  if (fileId != 0 && personalId <= 0) {
    _writeTag(inner, 3, 0);
    inner.add(sushiUvarint(fileId));
  }
  if (durationS != 0) {
    _writeTag(inner, 4, 0);
    inner.add(sushiUvarint(durationS < 0 ? 0 : durationS));
  }
  if (personalId > 0) {
    _writeTag(inner, 5, 0);
    inner.add(sushiUvarint(personalId));
  }
  return inner.toBytes();
}

/// WatchedEvent { episode_id = 1; bool done = 2; } — manual mark, one `ev` batch.
/// Season mark sends every catalog episode in one message (R-WRITE-3).
Future<void> sushiSendWatchedMarks(List<({int episodeId, bool done})> marks) async {
  final pending = [for (final mark in marks) if (mark.episodeId > 0) mark];
  if (pending.isEmpty) return;
  const chunk = 80;
  for (var i = 0; i < pending.length; i += chunk) {
    final end = i + chunk > pending.length ? pending.length : i + chunk;
    await _sendWatchedChunk(pending.sublist(i, end));
  }
}

Future<void> _sendWatchedChunk(List<({int episodeId, bool done})> marks) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null || assignment.pending || assignment.apiSendTargets.isEmpty) {
    return;
  }
  final events = BytesBuilder();
  _writeTag(events, 1, 0);
  events.add(sushiUvarint(DateTime.now().millisecondsSinceEpoch & 0x3fffffff));
  for (final mark in marks) {
    final inner = BytesBuilder();
    _writeTag(inner, 1, 0);
    inner.add(sushiUvarint(mark.episodeId));
    if (mark.done) {
      _writeTag(inner, 2, 0);
      inner.add(sushiUvarint(1));
    }
    final innerBytes = inner.toBytes();
    final event = BytesBuilder();
    _writeTag(event, 5, 2);
    event.add(sushiUvarint(innerBytes.length));
    event.add(innerBytes);
    final evBytes = event.toBytes();
    _writeTag(events, 2, 2);
    events.add(sushiUvarint(evBytes.length));
    events.add(evBytes);
  }
  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText('ev', corr, events.toBytes());
  try {
    await sushiSendTextFireAndForget(username: sushiNextApiBot(assignment), text: requestText);
  } catch (e) {
    debugPrint('[sushi] ev watched failed: $e');
  }
}

void _writeTag(BytesBuilder b, int field, int wire) =>
    b.add(sushiUvarint((field << 3) | wire));

/// FavEvent / LaterEvent share a body: { tmdb_id = 1; Kind kind = 2; bool on = 3; }.
Uint8List _flagInner({required int tmdbId, required int kind, required bool on}) {
  final inner = BytesBuilder();
  _writeTag(inner, 1, 0);
  inner.add(sushiUvarint(tmdbId));
  _writeTag(inner, 2, 0);
  inner.add(sushiUvarint(kind));
  if (on) {
    _writeTag(inner, 3, 0);
    inner.add(sushiUvarint(1));
  }
  return inner.toBytes();
}

/// Wraps one event body as `Events { seq, events = [ Event { <eventField> = <inner> } ] }` and
/// sends it down the `ev` command, fire-and-forget.
Future<void> _sendEvent({required int eventField, required Uint8List inner}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null ||
      assignment.pending ||
      assignment.apiSendTargets.isEmpty) {
    return;
  }
  final event = BytesBuilder();
  _writeTag(event, eventField, 2);
  event.add(sushiUvarint(inner.length));
  event.add(inner);

  final events = BytesBuilder();
  _writeTag(events, 1, 0);
  events.add(sushiUvarint(DateTime.now().millisecondsSinceEpoch & 0x3fffffff));
  _writeTag(events, 2, 2);
  final evBytes = event.toBytes();
  events.add(sushiUvarint(evBytes.length));
  events.add(evBytes);

  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText('ev', corr, events.toBytes());
  try {
    await sushiSendTextFireAndForget(
        username: sushiNextApiBot(assignment), text: requestText);
  } catch (e) {
    debugPrint('[sushi] ev failed: $e');
  }
}
