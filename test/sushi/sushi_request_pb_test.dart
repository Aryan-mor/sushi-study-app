import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/sushi_request_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

Uint8List _varintField(int field, int value) {
  final out = BytesBuilder();
  out.add(sushiUvarint((field << 3)));
  out.add(sushiUvarint(value));
  return out.toBytes();
}

void main() {
  test('sushiEncodeRequestReq writes tmdb_id (field 1) and kind (field 2)', () {
    final bytes = sushiEncodeRequestReq(tmdbId: 438631, kind: 2);
    // field 1, varint
    expect(bytes[0], 0x08);
    final id = sushiReadVarint(bytes, 1);
    expect(id.value, 438631);
    // field 2, varint
    expect(bytes[id.next], 0x10);
    expect(sushiReadVarint(bytes, id.next + 1).value, 2);
  });

  test('sushiEncodeRequestReq always writes kind even for a movie (server rejects unspecified)', () {
    final bytes = sushiEncodeRequestReq(tmdbId: 1, kind: 1);
    expect(bytes, containsAllInOrder([0x10, 1]));
  });

  test('the request line matches docs/02 grammar', () {
    final text = sushiEncodeRequestText('request', 'a', sushiEncodeRequestReq(tmdbId: 5, kind: 1));
    expect(text, startsWith('/request a '));
    expect(text, isNot(contains('=')));
  });

  test('SushiRequestRes decodes each outcome and the remaining count', () {
    for (final entry in {
      1: SushiRequestOutcome.accepted,
      2: SushiRequestOutcome.duplicate,
      3: SushiRequestOutcome.alreadyAvailable,
      4: SushiRequestOutcome.quotaExceeded,
      0: SushiRequestOutcome.unspecified,
    }.entries) {
      final out = BytesBuilder();
      out.add(_varintField(1, entry.key));
      out.add(_varintField(2, 7));
      final res = SushiRequestRes.decode(out.toBytes());
      expect(res.outcome, entry.value);
      expect(res.remainingToday, 7);
    }
  });

  test('SushiRequestRes tolerates an empty payload and unknown fields', () {
    expect(SushiRequestRes.decode(Uint8List(0)).outcome, SushiRequestOutcome.unspecified);
    final out = BytesBuilder();
    out.add(_varintField(1, 1));
    out.add(_varintField(9, 123)); // unknown field, must be skipped
    final res = SushiRequestRes.decode(out.toBytes());
    expect(res.outcome, SushiRequestOutcome.accepted);
  });

  test('an unknown future outcome value degrades to unspecified, not a crash', () {
    final res = SushiRequestRes.decode(_varintField(1, 99));
    expect(res.outcome, SushiRequestOutcome.unspecified);
  });
}
