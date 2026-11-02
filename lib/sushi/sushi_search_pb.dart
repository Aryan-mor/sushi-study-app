import 'dart:convert';
import 'dart:typed_data';

import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

/// Hand codecs for `sushi.v1.SearchReq` / `SearchRes` (docs/12 §6, ADR 0010).
class SushiSearchRes {
  const SushiSearchRes({
    required this.rows,
    required this.cursor,
    this.missing = const [],
  });

  final List<SushiRow> rows;
  final int cursor;
  final List<SushiRow> missing;

  static SushiSearchRes decode(Uint8List bytes) {
    final rows = <SushiRow>[];
    final missing = <SushiRow>[];
    var cursor = 0;
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final field = tagR.value >> 3;
      final wire = tagR.value & 0x7;
      switch (field) {
        case 1:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          rows.add(SushiRow.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          cursor = v.value;
        case 3:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          missing.add(SushiRow.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiSearchRes(
      rows: List.unmodifiable(rows),
      cursor: cursor,
      missing: List.unmodifiable(missing),
    );
  }
}

Uint8List sushiEncodeSearchReq({required String query, int cursor = 0}) {
  final out = BytesBuilder();
  void writeTag(int field, int wire) => out.add(sushiUvarint((field << 3) | wire));
  if (query.isNotEmpty) {
    writeTag(1, 2);
    final b = utf8.encode(query);
    out.add(sushiUvarint(b.length));
    out.add(b);
  }
  if (cursor != 0) {
    writeTag(2, 0);
    out.add(sushiUvarint(cursor));
  }
  return out.toBytes();
}
