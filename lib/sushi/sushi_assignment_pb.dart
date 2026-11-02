import 'dart:convert';
import 'dart:typed_data';

import 'package:fladder/sushi/sushi_wire.dart';

/// Hand-decode of `sushi.v1.Assignment` (proto/sushi/v1/bind.proto).
///
/// ```
/// string api_bot_username = 1;
/// repeated string pool = 2;
/// int32 provider_id = 3;
/// bytes binding_token = 4;
/// uint32 epoch = 5;
/// repeated string delivery_bots = 6;
/// ```
class SushiAssignmentPb {
  const SushiAssignmentPb({
    required this.apiBotUsername,
    required this.pool,
    required this.providerId,
    required this.bindingToken,
    required this.epoch,
    this.deliveryBots = const [],
  });

  final String apiBotUsername;
  final List<String> pool;
  final int providerId;
  final Uint8List bindingToken;
  final int epoch;

  /// Every delivery bot deliveryd round-robins across (docs/05 §6) — pre-started the same way
  /// the API pool is, so a reader's first play doesn't fail `400 chat not found` against
  /// whichever one the copy job happens to land on.
  final List<String> deliveryBots;

  /// Base64url (no pad) of [bindingToken] for prefs / JSON.
  String get bindingTokenBase64Url =>
      base64Url.encode(bindingToken).replaceAll('=', '');

  /// Decode protobuf payload bytes (envelope payload only, after flags).
  static SushiAssignmentPb decode(Uint8List bytes) {
    var apiBotUsername = '';
    final pool = <String>[];
    var providerId = 0;
    var bindingToken = Uint8List(0);
    var epoch = 0;
    final deliveryBots = <String>[];

    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final tag = tagR.value;
      final field = tag >> 3;
      final wire = tag & 0x7;

      switch (field) {
        case 1: // api_bot_username
          if (wire != 2) throw FormatException('field 1 wire $wire');
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          apiBotUsername = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 2: // pool (repeated)
          if (wire != 2) throw FormatException('field 2 wire $wire');
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          pool.add(utf8.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 3: // provider_id
          if (wire != 0) throw FormatException('field 3 wire $wire');
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          providerId = v.value;
        case 4: // binding_token
          if (wire != 2) throw FormatException('field 4 wire $wire');
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          bindingToken = Uint8List.fromList(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 5: // epoch
          if (wire != 0) throw FormatException('field 5 wire $wire');
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          epoch = v.value;
        case 6: // delivery_bots (repeated)
          if (wire != 2) throw FormatException('field 6 wire $wire');
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          deliveryBots.add(utf8.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }

    return SushiAssignmentPb(
      apiBotUsername: apiBotUsername,
      pool: List.unmodifiable(pool),
      providerId: providerId,
      bindingToken: bindingToken,
      epoch: epoch,
      deliveryBots: List.unmodifiable(deliveryBots),
    );
  }

  /// Encode for tests (proto3 wire).
  static Uint8List encode({
    required String apiBotUsername,
    List<String> pool = const [],
    int providerId = 0,
    List<int> bindingToken = const [],
    int epoch = 0,
    List<String> deliveryBots = const [],
  }) {
    final out = BytesBuilder();
    void writeTag(int field, int wire) =>
        out.add(sushiUvarint((field << 3) | wire));
    void writeBytes(List<int> b) {
      out.add(sushiUvarint(b.length));
      out.add(b);
    }

    if (apiBotUsername.isNotEmpty) {
      writeTag(1, 2);
      writeBytes(utf8.encode(apiBotUsername));
    }
    for (final p in pool) {
      writeTag(2, 2);
      writeBytes(utf8.encode(p));
    }
    if (providerId != 0) {
      writeTag(3, 0);
      out.add(sushiUvarint(providerId));
    }
    if (bindingToken.isNotEmpty) {
      writeTag(4, 2);
      writeBytes(bindingToken);
    }
    if (epoch != 0) {
      writeTag(5, 0);
      out.add(sushiUvarint(epoch));
    }
    for (final b in deliveryBots) {
      writeTag(6, 2);
      writeBytes(utf8.encode(b));
    }
    return out.toBytes();
  }
}
