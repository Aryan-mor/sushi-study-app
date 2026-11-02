import 'dart:convert';
import 'dart:typed_data';

import 'package:fladder/sushi/sushi_wire.dart';

/// Matches `be/internal/app/api/play.go` locatorPrefix (docs/05 §3).
const sushiLocatorPrefix = 'plm';

String sushiLocatorForFile(int fileId) => '${sushiLocatorPrefix}_$fileId';

/// Matches `be/internal/app/api/play.go` personalLocatorPrefix (ADR 0037). A personal video and a
/// catalog file can share a number; the prefix keeps their waiters apart.
const sushiPersonalLocatorPrefix = 'plp';

String sushiLocatorForPersonal(int personalId) => '${sushiPersonalLocatorPrefix}_$personalId';

/// Mirrors `sushi.v1.Mode`.
const sushiModeUnspecified = 0;
const sushiModeStream = 1;
const sushiModeDownload = 2;

/// A row that already exists: nothing to copy, hand back where it landed.
class SushiDelivered {
  const SushiDelivered({required this.botId, required this.messageId, required this.locator});

  /// When this instance comes from a `/play` reply (see [decode]) this is the backend's internal
  /// `bots.id` (a small FK into the deliveries → bots table), NOT the Telegram user id of the DM
  /// sender. It must never be passed to the native resolver as `providerBotId`: that field is
  /// checked against the message's real Telegram sender id and a server `bots.id` there fails every
  /// warm play as OX_DM_STALE (device log 2026-09-01). Only when this instance is built from a
  /// locally recorded `SushiTdlibDeliveryRef` is [botId] a real Telegram user id and safe to trust.
  final int botId;
  final int messageId;
  final String locator;

  static SushiDelivered decode(Uint8List bytes) {
    var botId = 0;
    var messageId = 0;
    var locator = '';
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
          botId = v.value;
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          messageId = v.value;
        case 3:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          locator = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiDelivered(botId: botId, messageId: messageId, locator: locator);
  }
}

/// The copy has been queued; deliveryd performs it out of band (docs/05 §4).
class SushiPending {
  const SushiPending({required this.locator});

  final String locator;

  static SushiPending decode(Uint8List bytes) {
    var locator = '';
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final field = tagR.value >> 3;
      final wire = tagR.value & 0x7;
      if (field == 1) {
        final lenR = sushiReadVarint(bytes, i);
        i = lenR.next;
        locator = utf8.decode(bytes.sublist(i, i + lenR.value));
        i += lenR.value;
      } else {
        i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiPending(locator: locator);
  }
}

/// Decoded `sushi.v1.PlayRes` — exactly one of [delivered]/[pending] is non-null.
class SushiPlayRes {
  const SushiPlayRes({this.delivered, this.pending});

  final SushiDelivered? delivered;
  final SushiPending? pending;

  static SushiPlayRes decode(Uint8List bytes) {
    SushiDelivered? delivered;
    SushiPending? pending;
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
          delivered = SushiDelivered.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          pending = SushiPending.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiPlayRes(delivered: delivered, pending: pending);
  }
}

/// Encodes a `sushi.v1.PlayReq`: field 1 `file_id` (varint), field 2 `force` (varint bool),
/// field 3 `mode` (varint enum), field 4 `personal_id` (varint, ADR 0037). Exactly one of
/// [fileId] / [personalId] is non-zero.
Uint8List sushiEncodePlayReq({
  required int fileId,
  int personalId = 0,
  bool force = false,
  int mode = sushiModeStream,
}) {
  final out = BytesBuilder();
  void writeTag(int field, int wire) => out.add(sushiUvarint((field << 3) | wire));
  if (fileId != 0) {
    writeTag(1, 0);
    out.add(sushiUvarint(fileId));
  }
  if (force) {
    writeTag(2, 0);
    out.add(sushiUvarint(1));
  }
  if (mode != 0) {
    writeTag(3, 0);
    out.add(sushiUvarint(mode));
  }
  if (personalId != 0) {
    writeTag(4, 0);
    out.add(sushiUvarint(personalId));
  }
  return out.toBytes();
}

/// Encodes a `sushi.v1.AckReq`: field 1 `file_id` (varint), field 2 `message_id` (varint),
/// field 3 `personal_id` (varint, ADR 0037).
Uint8List sushiEncodeAckReq({required int fileId, required int messageId, int personalId = 0}) {
  final out = BytesBuilder();
  void writeTag(int field, int wire) => out.add(sushiUvarint((field << 3) | wire));
  if (fileId != 0) {
    writeTag(1, 0);
    out.add(sushiUvarint(fileId));
  }
  if (messageId != 0) {
    writeTag(2, 0);
    out.add(sushiUvarint(messageId));
  }
  if (personalId != 0) {
    writeTag(3, 0);
    out.add(sushiUvarint(personalId));
  }
  return out.toBytes();
}
