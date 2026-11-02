import 'dart:convert';
import 'dart:typed_data';

import 'package:fladder/sushi/sushi_wire.dart';

/// Hand codecs for `sushi.v1.AppUpdateReq` / `AppUpdateRes` (ADR 0019).

class SushiAppUpdateRes {
  const SushiAppUpdateRes({
    required this.botId,
    required this.messageId,
    required this.version,
    required this.fileName,
    required this.locator,
  });

  final int botId;
  final int messageId;
  final String version;
  final String fileName;
  final String locator;

  static SushiAppUpdateRes decode(Uint8List bytes) {
    var botId = 0;
    var messageId = 0;
    var version = '';
    var fileName = '';
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
          version = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 4:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          fileName = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 5:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          locator = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiAppUpdateRes(
      botId: botId,
      messageId: messageId,
      version: version,
      fileName: fileName,
      locator: locator,
    );
  }
}

Uint8List sushiEncodeAppUpdateReq({required String platform}) {
  final out = BytesBuilder();
  if (platform.isEmpty) return out.toBytes();
  out.add(sushiUvarint((1 << 3) | 2));
  final bytes = utf8.encode(platform);
  out.add(sushiUvarint(bytes.length));
  out.add(bytes);
  return out.toBytes();
}

/// `sushi.v1.LatestApp` nested on HomeRes field 4.
class SushiLatestApp {
  const SushiLatestApp({required this.platform, required this.version});

  final String platform;
  final String version;

  static SushiLatestApp decode(Uint8List bytes) {
    var platform = '';
    var version = '';
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
          platform = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          version = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiLatestApp(platform: platform, version: version);
  }

  Map<String, Object?> toJson() => {'platform': platform, 'version': version};

  static SushiLatestApp? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final version = '${raw['version'] ?? ''}'.trim();
    if (version.isEmpty) return null;
    return SushiLatestApp(
      platform: '${raw['platform'] ?? ''}',
      version: version,
    );
  }
}
