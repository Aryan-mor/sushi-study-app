import 'dart:typed_data';

import 'package:fladder/sushi/sushi_wire.dart';

/// Hand codecs for `sushi.v1.RequestReq` / `RequestRes` (proto/sushi/v1/request.proto,
/// ADR 0014 §D2). Same compact style as [sushi_search_pb.dart].

/// sushi.v1.RequestOutcome. QUOTA_EXCEEDED is a normal answer with its own copy, never ERR_RATE.
enum SushiRequestOutcome {
  unspecified,
  accepted,
  duplicate,
  alreadyAvailable,
  quotaExceeded;

  static SushiRequestOutcome fromWire(int v) => switch (v) {
        1 => SushiRequestOutcome.accepted,
        2 => SushiRequestOutcome.duplicate,
        3 => SushiRequestOutcome.alreadyAvailable,
        4 => SushiRequestOutcome.quotaExceeded,
        _ => SushiRequestOutcome.unspecified,
      };
}

class SushiRequestRes {
  const SushiRequestRes({required this.outcome, required this.remainingToday});

  final SushiRequestOutcome outcome;
  final int remainingToday;

  static SushiRequestRes decode(Uint8List bytes) {
    var outcome = SushiRequestOutcome.unspecified;
    var remaining = 0;
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final field = tagR.value >> 3;
      final wire = tagR.value & 0x7;
      switch (field) {
        case 1:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          outcome = SushiRequestOutcome.fromWire(v.value);
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          remaining = v.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiRequestRes(outcome: outcome, remainingToday: remaining);
  }
}

/// `RequestReq { tmdb_id = 1; Kind kind = 2; }` — kind is 1 (movie) or 2 (series); proto3 omits it
/// when zero, but the server rejects an unspecified kind, so it is always written here.
Uint8List sushiEncodeRequestReq({required int tmdbId, required int kind}) {
  final out = BytesBuilder();
  void writeTag(int field, int wire) => out.add(sushiUvarint((field << 3) | wire));
  writeTag(1, 0);
  out.add(sushiUvarint(tmdbId));
  writeTag(2, 0);
  out.add(sushiUvarint(kind));
  return out.toBytes();
}
