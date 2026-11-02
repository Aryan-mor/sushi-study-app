import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

Uint8List _tag(int field, int wire) => Uint8List.fromList(sushiUvarint((field << 3) | wire));

Uint8List _lenDelim(int field, List<int> bytes) {
  final out = BytesBuilder();
  out.add(_tag(field, 2));
  out.add(sushiUvarint(bytes.length));
  out.add(bytes);
  return out.toBytes();
}

Uint8List _varintField(int field, int value) {
  final out = BytesBuilder();
  out.add(_tag(field, 0));
  out.add(sushiUvarint(value));
  return out.toBytes();
}

Uint8List _encodeRow({required int tmdbId, required int kind, required String title, required int year, required int rating, required String poster}) {
  final out = BytesBuilder();
  if (tmdbId != 0) out.add(_varintField(1, tmdbId));
  if (kind != 0) out.add(_varintField(2, kind));
  if (title.isNotEmpty) out.add(_lenDelim(3, utf8.encode(title)));
  if (year != 0) out.add(_varintField(4, year));
  if (rating != 0) out.add(_varintField(5, rating));
  if (poster.isNotEmpty) out.add(_lenDelim(6, utf8.encode(poster)));
  return out.toBytes();
}

Uint8List _encodeEpisode({required int episodeId, required int seasonNo, required int episodeNo, required String title}) {
  final out = BytesBuilder();
  if (episodeId != 0) out.add(_varintField(1, episodeId));
  if (seasonNo != 0) out.add(_varintField(2, seasonNo));
  if (episodeNo != 0) out.add(_varintField(3, episodeNo));
  if (title.isNotEmpty) out.add(_lenDelim(4, utf8.encode(title)));
  return out.toBytes();
}

Uint8List _encodeSeason({required int seasonNo, required int episodeCount}) {
  final out = BytesBuilder();
  if (seasonNo != 0) out.add(_varintField(1, seasonNo));
  if (episodeCount != 0) out.add(_varintField(2, episodeCount));
  return out.toBytes();
}

Uint8List _encodeItemRes({
  required Uint8List row,
  required String overview,
  required int releasedOn,
  required List<Uint8List> episodes,
  List<Uint8List> seasons = const [],
}) {
  final out = BytesBuilder();
  out.add(_lenDelim(1, row));
  if (overview.isNotEmpty) out.add(_lenDelim(2, utf8.encode(overview)));
  if (releasedOn != 0) out.add(_varintField(3, releasedOn));
  for (final e in episodes) {
    out.add(_lenDelim(4, e));
  }
  for (final s in seasons) {
    out.add(_lenDelim(15, s));
  }
  return out.toBytes();
}

Uint8List _encodeFile({
  required int fileId,
  required String qualityLabel,
  required int height,
  required String audioLangs,
  required String subLangs,
  required int sizeBytes,
  required int durationS,
  required int state,
}) {
  final out = BytesBuilder();
  if (fileId != 0) out.add(_varintField(1, fileId));
  if (qualityLabel.isNotEmpty) out.add(_lenDelim(2, utf8.encode(qualityLabel)));
  if (height != 0) out.add(_varintField(3, height));
  if (audioLangs.isNotEmpty) out.add(_lenDelim(4, utf8.encode(audioLangs)));
  if (subLangs.isNotEmpty) out.add(_lenDelim(5, utf8.encode(subLangs)));
  if (sizeBytes != 0) out.add(_varintField(6, sizeBytes));
  if (durationS != 0) out.add(_varintField(7, durationS));
  if (state != 0) out.add(_varintField(8, state));
  return out.toBytes();
}

void main() {
  test('sushiEncodeItemReq encodes tmdb_id and kind', () {
    final bytes = sushiEncodeItemReq(tmdbId: 603, kind: 2);
    final decoded = <int, int>{};
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final v = sushiReadVarint(bytes, i);
      i = v.next;
      decoded[tagR.value >> 3] = v.value;
    }
    expect(decoded[1], 603);
    expect(decoded[2], 2);
  });

  test('sushiEncodeFilesReq encodes episode_id', () {
    final bytes = sushiEncodeFilesReq(episodeId: 42);
    expect(bytes, [0x08, 42]);
  });

  test('SushiItemRes decodes row, overview, releasedOn and episodes', () {
    final rowBytes = _encodeRow(tmdbId: 603, kind: 1, title: 'The Matrix', year: 1999, rating: 87, poster: 'abc');
    final ep1 = _encodeEpisode(episodeId: 100, seasonNo: 0, episodeNo: 0, title: 'Movie');
    final itemBytes = _encodeItemRes(
      row: rowBytes,
      overview: 'A hacker discovers reality is a simulation.',
      releasedOn: 915148800,
      episodes: [ep1],
    );

    final res = SushiItemRes.decode(itemBytes);
    expect(res.row.tmdbId, 603);
    expect(res.row.title, 'The Matrix');
    expect(res.overview, 'A hacker discovers reality is a simulation.');
    expect(res.releasedOn, 915148800);
    expect(res.episodes, hasLength(1));
    expect(res.episodes.single.episodeId, 100);
  });

  test('SushiItemRes decodes season index and a single play-target', () {
    final rowBytes = _encodeRow(tmdbId: 1, kind: 2, title: 'A Show', year: 2020, rating: 70, poster: '');
    final ep1 = _encodeEpisode(episodeId: 10, seasonNo: 1, episodeNo: 1, title: 'Pilot');
    final s1 = _encodeSeason(seasonNo: 1, episodeCount: 2);
    final s2 = _encodeSeason(seasonNo: 2, episodeCount: 1);
    final itemBytes = _encodeItemRes(
      row: rowBytes,
      overview: '',
      releasedOn: 0,
      episodes: [ep1],
      seasons: [s1, s2],
    );

    final res = SushiItemRes.decode(itemBytes);
    expect(res.episodes, hasLength(1));
    expect(res.episodes.single.episodeId, 10);
    expect(res.seasons, hasLength(2));
    expect(res.seasons[0].seasonNo, 1);
    expect(res.seasons[0].episodeCount, 2);
    expect(res.seasons[1].seasonNo, 2);
    expect(sushiItemResPlayable(res), isTrue);
  });

  test('sushiEncodeEpisodesReq encodes tmdb, kind, season, page', () {
    final bytes = sushiEncodeEpisodesReq(tmdbId: 1396, kind: 2, seasonNo: 1, page: 3);
    final decoded = <int, int>{};
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final v = sushiReadVarint(bytes, i);
      i = v.next;
      decoded[tagR.value >> 3] = v.value;
    }
    expect(decoded[1], 1396);
    expect(decoded[2], 2);
    expect(decoded[3], 1);
    expect(decoded[4], 3);
  });

  test('SushiEpisodesRes decodes a season page', () {
    final ep1 = _encodeEpisode(episodeId: 10, seasonNo: 1, episodeNo: 1, title: 'Pilot');
    final ep2 = _encodeEpisode(episodeId: 11, seasonNo: 1, episodeNo: 2, title: 'Two');
    final out = BytesBuilder()
      ..add(_lenDelim(1, ep1))
      ..add(_lenDelim(1, ep2))
      ..add(_varintField(2, 0))
      ..add(_varintField(3, 2));
    final res = SushiEpisodesRes.decode(out.toBytes());
    expect(res.episodes, hasLength(2));
    expect(res.episodes[1].title, 'Two');
    expect(res.page, 0);
    expect(res.pages, 2);
  });

  test('SushiItemRes decodes logo, people, related and collection', () {
    final rowBytes = _encodeRow(tmdbId: 603, kind: 1, title: 'The Matrix', year: 1999, rating: 87, poster: 'abc');
    final related = _encodeRow(tmdbId: 604, kind: 1, title: 'Reloaded', year: 2003, rating: 70, poster: 'rel');
    final person = BytesBuilder()
      ..add(_lenDelim(1, utf8.encode('Keanu Reeves')))
      ..add(_lenDelim(2, utf8.encode('Neo')));
    final out = BytesBuilder()
      ..add(_lenDelim(1, rowBytes))
      ..add(_lenDelim(5, utf8.encode('wordmark')))
      ..add(_lenDelim(9, person.toBytes()))
      ..add(_lenDelim(10, related))
      ..add(_lenDelim(11, utf8.encode('The Matrix Collection')))
      ..add(_lenDelim(12, related));
    final res = SushiItemRes.decode(out.toBytes());
    expect(res.logo, 'wordmark');
    expect(res.people.single.name, 'Keanu Reeves');
    expect(res.people.single.role, 'Neo');
    expect(res.related.single.tmdbId, 604);
    expect(res.collectionName, 'The Matrix Collection');
    expect(res.collection.single.title, 'Reloaded');
  });

  test('SushiFilesRes decodes multiple files with correct state mapping', () {
    final f1 = _encodeFile(
      fileId: 5,
      qualityLabel: '1080p',
      height: 1080,
      audioLangs: 'fa,en',
      subLangs: 'en',
      sizeBytes: 1500000000,
      durationS: 7200,
      state: 1,
    );
    final f2 = _encodeFile(
      fileId: 6,
      qualityLabel: '480p',
      height: 480,
      audioLangs: 'en',
      subLangs: '',
      sizeBytes: 400000000,
      durationS: 7200,
      state: 3,
    );
    final out = BytesBuilder();
    out.add(_lenDelim(1, f1));
    out.add(_lenDelim(1, f2));

    final res = SushiFilesRes.decode(out.toBytes());
    expect(res.files, hasLength(2));
    expect(res.files[0].qualityLabel, '1080p');
    expect(res.files[0].audioLangs, 'fa,en');
    expect(res.files[0].state, SushiFileState.ready);
    expect(res.files[1].state, SushiFileState.unavailable);
  });

  test('SushiFilesRes decodes episode progress', () {
    final f1 = _encodeFile(
      fileId: 5,
      qualityLabel: '1080p',
      height: 1080,
      audioLangs: 'en',
      subLangs: '',
      sizeBytes: 1,
      durationS: 7200,
      state: 1,
    );
    final out = BytesBuilder()
      ..add(_lenDelim(1, f1))
      ..add(_varintField(2, 1200))
      ..add(_varintField(3, 1))
      ..add(_varintField(4, 5));
    final res = SushiFilesRes.decode(out.toBytes());
    expect(res.positionS, 1200);
    expect(res.done, isTrue);
    expect(res.lastFileId, 5);
    expect(res.resumeDurationS, 7200);
  });

  test('SushiFilesRes decodes empty list', () {
    final res = SushiFilesRes.decode(Uint8List(0));
    expect(res.files, isEmpty);
  });

  test('SushiItemRes decodes trailer_key, defaults to empty', () {
    final rowBytes = _encodeRow(tmdbId: 603, kind: 1, title: 'The Matrix', year: 1999, rating: 87, poster: 'abc');
    expect(SushiItemRes.decode(_lenDelim(1, rowBytes)).trailerKey, '');

    final out = BytesBuilder()
      ..add(_lenDelim(1, rowBytes))
      ..add(_lenDelim(16, utf8.encode('dQw4w9WgXcQ')));
    expect(SushiItemRes.decode(out.toBytes()).trailerKey, 'dQw4w9WgXcQ');
  });

  test('SushiItemRes decodes country', () {
    final rowBytes = _encodeRow(tmdbId: 603, kind: 1, title: 'The Matrix', year: 1999, rating: 87, poster: 'abc');
    expect(SushiItemRes.decode(_lenDelim(1, rowBytes)).country, '');
    final out = BytesBuilder()
      ..add(_lenDelim(1, rowBytes))
      ..add(_lenDelim(17, utf8.encode('US')));
    expect(SushiItemRes.decode(out.toBytes()).country, 'US');
  });
}
