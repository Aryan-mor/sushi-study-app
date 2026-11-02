import 'dart:convert';
import 'dart:typed_data';

import 'package:fladder/sushi/sushi_wire.dart';

/// Hand codecs for `sushi.v1.PrefsReq` / `PrefsRes` (proto/sushi/v1/prefs.proto, doc 15 §12).

class SushiPrefsRes {
  const SushiPrefsRes({required this.hasGeminiKey, required this.geminiApiKey});

  final bool hasGeminiKey;
  final String geminiApiKey;

  static SushiPrefsRes decode(Uint8List bytes) {
    var hasKey = false;
    var key = '';
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
          hasKey = v.value != 0;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          key = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiPrefsRes(hasGeminiKey: hasKey, geminiApiKey: key);
  }
}
