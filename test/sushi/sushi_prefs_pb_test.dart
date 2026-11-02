import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/sushi_prefs_pb.dart';
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

void main() {
  test('SushiPrefsRes decodes has_gemini_key and gemini_api_key', () {
    final out = BytesBuilder();
    out.add(_varintField(1, 1));
    out.add(_lenDelim(2, utf8.encode('AIzaSyDummyKeyForTestsOnly1234567890AB')));
    final res = SushiPrefsRes.decode(out.toBytes());
    expect(res.hasGeminiKey, isTrue);
    expect(res.geminiApiKey, 'AIzaSyDummyKeyForTestsOnly1234567890AB');
  });

  test('SushiPrefsRes empty payload is no key', () {
    final res = SushiPrefsRes.decode(Uint8List(0));
    expect(res.hasGeminiKey, isFalse);
    expect(res.geminiApiKey, isEmpty);
  });

  test('prefs request line is a bare command with corr', () {
    final text = sushiEncodeRequestText('prefs', 'a', Uint8List(0));
    expect(text, '/prefs a');
  });
}
