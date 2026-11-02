import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:libcompress/libcompress.dart';

/// Shared wire-format primitives for the Sushi bot protocol (docs/03-wire-format.md,
/// docs/02-bot-protocol.md §3).
///
/// Split out so every reply message type (Assignment, HomeRes, ...) decodes through one envelope
/// reader instead of each caller re-walking the version/corr/type/flags header itself.

/// Match sushi `wire.MaxPayload` (8 MiB) so a malicious frame cannot OOM the client.
final sushiZstd = ZstdCodec(maxDecompressedSize: 8 << 20);

/// Proto3 unsigned-varint encoder.
List<int> sushiUvarint(int n) {
  final out = <int>[];
  var x = n;
  while (x >= 0x80) {
    out.add((x & 0x7f) | 0x80);
    x >>= 7;
  }
  out.add(x);
  return out;
}

/// Proto3 unsigned-varint decoder.
({int value, int next}) sushiReadVarint(Uint8List bytes, int offset) {
  var result = 0;
  var shift = 0;
  var i = offset;
  while (i < bytes.length) {
    final b = bytes[i++];
    result |= (b & 0x7f) << shift;
    if ((b & 0x80) == 0) {
      return (value: result, next: i);
    }
    shift += 7;
    if (shift > 63) {
      throw const FormatException('varint too long');
    }
  }
  throw const FormatException('truncated varint');
}

/// Skips one unknown protobuf field, positioned just after its tag varint.
int sushiSkipField(Uint8List bytes, int i, int wire) {
  switch (wire) {
    case 0:
      return sushiReadVarint(bytes, i).next;
    case 1:
      return i + 8;
    case 2:
      final lenR = sushiReadVarint(bytes, i);
      return lenR.next + lenR.value;
    case 5:
      return i + 4;
    default:
      throw FormatException('unsupported wire type $wire');
  }
}

/// A random base36 correlation id — the second whitespace-separated field of a request line
/// (docs/02 §3).
String sushiNewCorrBase36() {
  final n = Random.secure().nextInt(0x3fffffff) + 1;
  return n.toRadixString(36);
}

String sushiPadBase64Url(String s) {
  final mod = s.length % 4;
  if (mod == 0) return s;
  return s.padRight(s.length + (4 - mod), '=');
}

/// A decoded reply envelope: `!` + base64url(ver:u8=1, corr:varint, type:varint, flags:varint,
/// payload) (docs/03-wire-format.md). [payload] is already zstd-decompressed if flag bit 0 was set.
class SushiEnvelope {
  const SushiEnvelope({required this.corr, required this.type, required this.payload});

  final int corr;
  final int type;
  final Uint8List payload;

  static const int flagCompressed = 1 << 0;

  // sushi.v1.MsgType (proto/sushi/v1/protocol.proto) — only the values the client currently acts on.
  static const int msgTypeHomeRes = 2;
  static const int msgTypeSearchRes = 8;
  static const int msgTypeErr = 14;
  static const int msgTypeAssignment = 15;
  static const int msgTypeEpisodesRes = 33;
  static const int msgTypeSubtitleRes = 35;
  static const int msgTypeSubtitleFileRes = 37;

  /// Throws [FormatException] on any structural problem (missing `!`, bad base64, unsupported
  /// version, truncated varints). Callers decide what a decode failure means for their message.
  static SushiEnvelope decode(String reply) {
    final trimmed = reply.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('!')) {
      throw const FormatException('reply missing ! marker');
    }
    final bytes = Uint8List.fromList(base64Url.decode(sushiPadBase64Url(trimmed.substring(1))));
    if (bytes.isEmpty) {
      throw const FormatException('empty envelope');
    }
    final ver = bytes[0];
    if (ver != 1) {
      throw FormatException('unsupported envelope version $ver');
    }
    var offset = 1;
    final corrR = sushiReadVarint(bytes, offset);
    offset = corrR.next;
    final typeR = sushiReadVarint(bytes, offset);
    offset = typeR.next;
    final flagsR = sushiReadVarint(bytes, offset);
    offset = flagsR.next;
    var payload = bytes.sublist(offset);
    if ((flagsR.value & flagCompressed) != 0) {
      payload = sushiZstd.decompress(payload);
    }
    return SushiEnvelope(corr: corrR.value, type: typeR.value, payload: payload);
  }
}

/// Builds the plain-text request line a client sends *to* a bot (docs/02 §3):
/// `/<command> <corr-base36>[ <base64url(proto bytes)>]` — no envelope and no compression on this
/// side (confirmed against `ParseRequest`/`decodeArgs` in
/// be/internal/adapter/transport/tg/{transport,support}.go).
String sushiEncodeRequestText(String command, String corrBase36, Uint8List protoBytes) {
  final argsToken = protoBytes.isEmpty ? '' : ' ${base64Url.encode(protoBytes).replaceAll('=', '')}';
  return '/$command $corrBase36$argsToken';
}
