import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
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

Uint8List _encodeRow({
  required int tmdbId,
  required int kind,
  required String title,
  required int year,
  required int rating,
  required String poster,
}) {
  final out = BytesBuilder();
  if (tmdbId != 0) out.add(_varintField(1, tmdbId));
  if (kind != 0) out.add(_varintField(2, kind));
  if (title.isNotEmpty) out.add(_lenDelim(3, utf8.encode(title)));
  if (year != 0) out.add(_varintField(4, year));
  if (rating != 0) out.add(_varintField(5, rating));
  if (poster.isNotEmpty) out.add(_lenDelim(6, utf8.encode(poster)));
  return out.toBytes();
}

Uint8List _encodeRail({required int kind, required List<Uint8List> rows}) {
  final out = BytesBuilder();
  if (kind != 0) out.add(_varintField(1, kind));
  for (final r in rows) {
    out.add(_lenDelim(2, r));
  }
  return out.toBytes();
}

Uint8List _encodeHomeRes({required List<Uint8List> rails, int seq = 0, int ttl = 0}) {
  final out = BytesBuilder();
  for (final r in rails) {
    out.add(_lenDelim(1, r));
  }
  if (seq != 0) out.add(_varintField(2, seq));
  if (ttl != 0) out.add(_varintField(3, ttl));
  return out.toBytes();
}

void main() {
  test('sushiEncodeHomeReq encodes tab and since_seq as varint fields', () {
    final bytes = sushiEncodeHomeReq(tab: sushiHomeTabSeries, sinceSeq: 42);
    expect(bytes, [0x08, sushiHomeTabSeries, 0x10, 42]);
  });

  test('sushiEncodeHomeReq appends platform as a length-delimited field', () {
    final bytes = sushiEncodeHomeReq(tab: sushiHomeTabMovies, platform: 'windows');
    expect(bytes.first, 0x08);
    expect(bytes[1], sushiHomeTabMovies);
    expect(bytes[2], 0x1a); // field 3, wire 2
  });

  test('sushiEncodeHomeReq appends current_version as field 4', () {
    final bytes = sushiEncodeHomeReq(
      tab: sushiHomeTabMovies,
      platform: 'android_new',
      currentVersion: '1.1.191',
    );
    expect(bytes.contains(0x22), isTrue); // field 4, wire 2
  });

  test('sushiEncodeHomeReq omits zero-value fields', () {
    expect(sushiEncodeHomeReq(tab: 0, sinceSeq: 0), isEmpty);
  });

  test('SushiRow decodes all fields', () {
    final bytes = _encodeRow(tmdbId: 603, kind: 1, title: 'The Matrix', year: 1999, rating: 87, poster: 'abc123');
    final row = SushiRow.decode(bytes);
    expect(row.tmdbId, 603);
    expect(row.kind, SushiKind.movie);
    expect(row.title, 'The Matrix');
    expect(row.year, 1999);
    expect(row.rating, 87);
    expect(row.poster, 'abc123');
  });

  test('SushiRow with poster/year unset decodes to zero-value defaults, not a crash', () {
    final bytes = _encodeRow(tmdbId: 1, kind: 2, title: 'Unknown Year Show', year: 0, rating: 0, poster: '');
    final row = SushiRow.decode(bytes);
    expect(row.kind, SushiKind.series);
    expect(row.year, 0);
    expect(row.rating, 0);
    expect(row.poster, isEmpty);
  });

  test('SushiHomeRes decodes multiple rails and rowsFor finds the right one', () {
    final sliderRow = _encodeRow(tmdbId: 1, kind: 1, title: 'Slider Movie', year: 2024, rating: 90, poster: 'p1');
    final watchedRow1 = _encodeRow(tmdbId: 2, kind: 1, title: 'Watched One', year: 2020, rating: 70, poster: 'p2');
    final watchedRow2 = _encodeRow(tmdbId: 3, kind: 2, title: 'Watched Two', year: 2021, rating: 60, poster: '');

    final sliderRail = _encodeRail(kind: 1, rows: [sliderRow]);
    final watchedRail = _encodeRail(kind: 2, rows: [watchedRow1, watchedRow2]);

    final homeResBytes = _encodeHomeRes(rails: [sliderRail, watchedRail], seq: 5, ttl: 3600);
    final res = SushiHomeRes.decode(homeResBytes);

    expect(res.seq, 5);
    expect(res.ttlSeconds, 3600);
    expect(res.rails.length, 2);

    final slider = res.rowsFor(SushiRailKind.slider);
    expect(slider, hasLength(1));
    expect(slider.single.title, 'Slider Movie');

    final watched = res.rowsFor(SushiRailKind.mostWatched);
    expect(watched, hasLength(2));
    expect(watched.map((r) => r.title), ['Watched One', 'Watched Two']);

    expect(res.rowsFor(SushiRailKind.trending), isEmpty);
    expect(res.latestApp, isNull);
  });

  test('SushiHomeRes decodes not_interested', () {
    final title = BytesBuilder()
      ..add(_varintField(1, 603))
      ..add(_varintField(2, 1));
    final out = BytesBuilder()
      ..add(_varintField(2, 4))
      ..add(_lenDelim(5, title.toBytes()));
    final res = SushiHomeRes.decode(out.toBytes());
    expect(res.seq, 4);
    expect(res.notInterested, hasLength(1));
    expect(res.notInterested.single.tmdbId, 603);
    expect(res.notInterested.single.kind, SushiKind.movie);
  });

  test('SushiHomeRes decodes latest_app', () {
    final latest = BytesBuilder()
      ..add(_lenDelim(1, utf8.encode('android_new')))
      ..add(_lenDelim(2, utf8.encode('1.2.0')));
    final out = BytesBuilder()
      ..add(_varintField(2, 9))
      ..add(_lenDelim(4, latest.toBytes()));
    final res = SushiHomeRes.decode(out.toBytes());
    expect(res.seq, 9);
    expect(res.latestApp?.platform, 'android_new');
    expect(res.latestApp?.version, '1.2.0');
  });

  test('sushiEncodeRequestText matches docs/02 §3 grammar for a bare command', () {
    final text = sushiEncodeRequestText('home', '7', Uint8List(0));
    expect(text, '/home 7');
  });

  test('sushiEncodeRequestText appends unpadded base64url args when present', () {
    final proto = sushiEncodeHomeReq(tab: sushiHomeTabMovies);
    final text = sushiEncodeRequestText('home', '9', proto);
    expect(text, startsWith('/home 9 '));
    expect(text, isNot(contains('=')));
  });
}
