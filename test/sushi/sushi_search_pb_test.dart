import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_search_pb.dart';
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
}) {
  final out = BytesBuilder();
  out.add(_varintField(1, tmdbId));
  out.add(_varintField(2, kind));
  out.add(_lenDelim(3, utf8.encode(title)));
  return out.toBytes();
}

void main() {
  test('sushiEncodeSearchReq writes query as length-delimited field 1', () {
    final bytes = sushiEncodeSearchReq(query: 'tenet');
    expect(bytes[0], 0x0a);
    final len = sushiReadVarint(bytes, 1);
    expect(utf8.decode(bytes.sublist(len.next, len.next + len.value)), 'tenet');
  });

  test('sushiEncodeSearchReq omits empty query and zero cursor', () {
    expect(sushiEncodeSearchReq(query: '', cursor: 0), isEmpty);
  });

  test('sushiEncodeSearchReq writes non-zero cursor as field 2', () {
    final bytes = sushiEncodeSearchReq(query: 'x', cursor: 20);
    expect(bytes, containsAllInOrder([0x10, 20]));
  });

  test('SushiSearchRes decodes rows and next-page cursor', () {
    final out = BytesBuilder();
    out.add(_lenDelim(1, _encodeRow(tmdbId: 27205, kind: 1, title: 'Inception')));
    out.add(_lenDelim(1, _encodeRow(tmdbId: 1396, kind: 2, title: 'Breaking Bad')));
    out.add(_varintField(2, 20));

    final res = SushiSearchRes.decode(out.toBytes());
    expect(res.cursor, 20);
    expect(res.rows, hasLength(2));
    expect(res.rows[0].tmdbId, 27205);
    expect(res.rows[0].kind, SushiKind.movie);
    expect(res.rows[0].title, 'Inception');
    expect(res.rows[1].kind, SushiKind.series);
    expect(res.rows[1].title, 'Breaking Bad');
    expect(res.missing, isEmpty);
  });

  test('SushiSearchRes decodes missing field 3', () {
    final out = BytesBuilder();
    out.add(_lenDelim(1, _encodeRow(tmdbId: 1, kind: 1, title: 'Have')));
    out.add(_lenDelim(3, _encodeRow(tmdbId: 99, kind: 1, title: 'Ghost')));
    out.add(_lenDelim(3, _encodeRow(tmdbId: 100, kind: 2, title: 'Ghost Show')));

    final res = SushiSearchRes.decode(out.toBytes());
    expect(res.rows, hasLength(1));
    expect(res.missing, hasLength(2));
    expect(res.missing[0].tmdbId, 99);
    expect(res.missing[0].title, 'Ghost');
    expect(res.missing[1].kind, SushiKind.series);
  });

  test('sushiEncodeRequestText search line matches docs/02 grammar', () {
    final proto = sushiEncodeSearchReq(query: 'tenet');
    final text = sushiEncodeRequestText('search', '9', proto);
    expect(text, startsWith('/search 9 '));
    expect(text, isNot(contains('=')));
  });
}
