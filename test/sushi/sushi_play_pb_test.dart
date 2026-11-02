import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/sushi_play_pb.dart';
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

Uint8List _encodeDelivered({required int botId, required int messageId, required String locator}) {
  final out = BytesBuilder();
  if (botId != 0) out.add(_varintField(1, botId));
  if (messageId != 0) out.add(_varintField(2, messageId));
  if (locator.isNotEmpty) out.add(_lenDelim(3, utf8.encode(locator)));
  return out.toBytes();
}

Uint8List _encodePending(String locator) {
  final out = BytesBuilder();
  if (locator.isNotEmpty) out.add(_lenDelim(1, utf8.encode(locator)));
  return out.toBytes();
}

void main() {
  test('sushiEncodePlayReq encodes file_id, force and mode as varint fields', () {
    final bytes = sushiEncodePlayReq(fileId: 4211, force: true, mode: sushiModeDownload);
    final decoded = <int, int>{};
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final v = sushiReadVarint(bytes, i);
      i = v.next;
      decoded[tagR.value >> 3] = v.value;
    }
    expect(decoded[1], 4211);
    expect(decoded[2], 1);
    expect(decoded[3], sushiModeDownload);
  });

  test('sushiEncodePlayReq omits force and mode when unset (mode defaults to stream)', () {
    final bytes = sushiEncodePlayReq(fileId: 42);
    // field 1 (file_id=42), field 3 (mode=1, the sushiModeStream default) — no force field.
    expect(bytes, [0x08, 42, 0x18, 1]);
  });

  test('sushiEncodeAckReq encodes file_id and message_id', () {
    final bytes = sushiEncodeAckReq(fileId: 4211, messageId: 987654);
    expect(bytes, [0x08, ...sushiUvarint(4211), 0x10, ...sushiUvarint(987654)]);
  });

  test('SushiPlayRes decodes a Delivered outcome', () {
    final bytes = _lenDelim(1, _encodeDelivered(botId: 5, messageId: 555111, locator: 'plm_4211'));
    final res = SushiPlayRes.decode(bytes);
    expect(res.pending, isNull);
    expect(res.delivered, isNotNull);
    expect(res.delivered!.botId, 5);
    expect(res.delivered!.messageId, 555111);
    expect(res.delivered!.locator, 'plm_4211');
  });

  test('SushiPlayRes decodes a Pending outcome', () {
    final bytes = _lenDelim(2, _encodePending('plm_4211'));
    final res = SushiPlayRes.decode(bytes);
    expect(res.delivered, isNull);
    expect(res.pending, isNotNull);
    expect(res.pending!.locator, 'plm_4211');
  });
}
