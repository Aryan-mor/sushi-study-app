import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/sushi_sync_pb.dart';
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

Uint8List _encodeWatchedState({required int episodeId, required bool done}) {
  final out = BytesBuilder();
  if (episodeId != 0) out.add(_varintField(1, episodeId));
  if (done) out.add(_varintField(2, 1));
  return out.toBytes();
}

void main() {
  test('sushiEncodeSyncReq encodes watched_watermark, omits zero', () {
    expect(sushiEncodeSyncReq(watchedWatermark: 0), isEmpty);
    final bytes = sushiEncodeSyncReq(watchedWatermark: 42);
    final tagR = sushiReadVarint(bytes, 0);
    expect(tagR.value >> 3, 1);
    final v = sushiReadVarint(bytes, tagR.next);
    expect(v.value, 42);
  });

  test('SushiSyncRes decodes watched rows, watermark and watched_more', () {
    final w1 = _encodeWatchedState(episodeId: 1, done: true);
    final w2 = _encodeWatchedState(episodeId: 2, done: false);
    final out = BytesBuilder()
      ..add(_lenDelim(1, w1))
      ..add(_lenDelim(1, w2))
      ..add(_varintField(2, 30))
      ..add(_varintField(3, 1));

    final res = SushiSyncRes.decode(out.toBytes());
    expect(res.watched, hasLength(2));
    expect(res.watched[0].episodeId, 1);
    expect(res.watched[0].done, isTrue);
    expect(res.watched[1].episodeId, 2);
    expect(res.watched[1].done, isFalse);
    expect(res.watchedWatermark, 30);
    expect(res.watchedMore, isTrue);
  });

  test('SushiSyncRes decodes an empty reply (nothing new)', () {
    final res = SushiSyncRes.decode(Uint8List(0));
    expect(res.watched, isEmpty);
    expect(res.watchedWatermark, 0);
    expect(res.watchedMore, isFalse);
  });

  // Same bytes as syncPrefsVector in sushi/be/internal/app/api/playback_prefs_test.go (R-PROTO-2):
  // SyncRes{watched_watermark: 30, audio_pref: "original", max_height: 1080}.
  test('SushiSyncRes decodes the playback prefs vector shared with the server', () {
    const hex = '101e22086f726967696e616c28b808';
    final bytes = Uint8List.fromList([
      for (var k = 0; k < hex.length; k += 2) int.parse(hex.substring(k, k + 2), radix: 16),
    ]);
    final res = SushiSyncRes.decode(bytes);
    expect(res.watchedWatermark, 30);
    expect(res.audioPref, 'original');
    expect(res.maxHeight, 1080);
    expect(res.subtitleLang, isEmpty);
    expect(res.watched, isEmpty);
  });

  test('SushiSyncRes decodes subtitle_lang', () {
    final out = BytesBuilder()
      ..add(_varintField(2, 30))
      ..add(_lenDelim(4, 'original'.codeUnits))
      ..add(_varintField(5, 1080))
      ..add(_lenDelim(6, 'fa'.codeUnits));
    final res = SushiSyncRes.decode(out.toBytes());
    expect(res.subtitleLang, 'fa');
    expect(res.audioPref, 'original');
    expect(res.maxHeight, 1080);
    expect(res.subs, isEmpty);
  });

  test('SushiSyncRes decodes subs', () {
    final out = BytesBuilder()
      ..add(_lenDelim(6, 'en'.codeUnits))
      ..add(_lenDelim(7, 'on'.codeUnits));
    final res = SushiSyncRes.decode(out.toBytes());
    expect(res.subtitleLang, 'en');
    expect(res.subs, 'on');
  });

  test('SushiSyncRes from an older server has no prefs', () {
    final res = SushiSyncRes.decode(_varintField(2, 30));
    expect(res.audioPref, isEmpty);
    expect(res.maxHeight, 0);
  });
}
