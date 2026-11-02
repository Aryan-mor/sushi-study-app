import 'dart:convert';
import 'dart:typed_data';

import 'package:fladder/sushi/sushi_wire.dart';

/// Hand codecs for `sushi.v1.SubtitleReq` / `SubtitleRes` / `SubtitleFileReq` / `SubtitleFileRes`
/// (doc 15 §7, proto/sushi/v1/subtitle.proto). Server-proxied subtitle search + fetch — the
/// provider API key never reaches the client.

class SushiSubtitlePack {
  const SushiSubtitlePack({
    required this.tag,
    required this.releaseName,
    required this.releases,
    required this.lang,
    required this.translator,
    required this.hi,
  });

  final String tag;
  final String releaseName;
  final List<String> releases;
  final String lang;
  final String translator;
  final bool hi;

  static SushiSubtitlePack decode(Uint8List bytes) {
    var tag = '';
    var releaseName = '';
    final releases = <String>[];
    var lang = '';
    var translator = '';
    var hi = false;
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
          tag = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          releaseName = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 3:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          releases.add(utf8.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 4:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          lang = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 5:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          translator = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 6:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          hi = v.value != 0;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiSubtitlePack(
      tag: tag,
      releaseName: releaseName,
      releases: List.unmodifiable(releases),
      lang: lang,
      translator: translator,
      hi: hi,
    );
  }
}

class SushiSubtitleRes {
  const SushiSubtitleRes({required this.packs});

  final List<SushiSubtitlePack> packs;

  static SushiSubtitleRes decode(Uint8List bytes) {
    final packs = <SushiSubtitlePack>[];
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final field = tagR.value >> 3;
      final wire = tagR.value & 0x7;
      if (field == 1) {
        final lenR = sushiReadVarint(bytes, i);
        i = lenR.next;
        packs.add(SushiSubtitlePack.decode(bytes.sublist(i, i + lenR.value)));
        i += lenR.value;
      } else {
        i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiSubtitleRes(packs: List.unmodifiable(packs));
  }
}

/// A reference to a subtitle file copy in the reader's own chat (doc 15 §7), never the text
/// itself -- see subtitle.proto's SubtitleFileRes doc comment for why.
class SushiSubtitleFileRes {
  const SushiSubtitleFileRes({required this.botId, required this.messageId, required this.ext});

  final int botId;
  final int messageId;
  final String ext;

  static SushiSubtitleFileRes decode(Uint8List bytes) {
    var botId = 0;
    var messageId = 0;
    var ext = '';
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
          ext = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiSubtitleFileRes(botId: botId, messageId: messageId, ext: ext);
  }
}

/// Encodes a `sushi.v1.SubtitleReq`: tmdb_id (1), kind (2), season_no (3), episode_no (4),
/// lang (5), duration_min (6), source_label (7).
Uint8List sushiEncodeSubtitleReq({
  required int tmdbId,
  required int kind,
  int seasonNo = 0,
  int episodeNo = 0,
  String lang = '',
  int durationMin = 0,
  String sourceLabel = '',
}) {
  final out = BytesBuilder();
  void writeTag(int field, int wire) => out.add(sushiUvarint((field << 3) | wire));
  if (tmdbId != 0) {
    writeTag(1, 0);
    out.add(sushiUvarint(tmdbId));
  }
  if (kind != 0) {
    writeTag(2, 0);
    out.add(sushiUvarint(kind));
  }
  if (seasonNo != 0) {
    writeTag(3, 0);
    out.add(sushiUvarint(seasonNo));
  }
  if (episodeNo != 0) {
    writeTag(4, 0);
    out.add(sushiUvarint(episodeNo));
  }
  if (lang.isNotEmpty) {
    writeTag(5, 2);
    final b = utf8.encode(lang);
    out.add(sushiUvarint(b.length));
    out.add(b);
  }
  if (durationMin > 0) {
    writeTag(6, 0);
    out.add(sushiUvarint(durationMin));
  }
  if (sourceLabel.isNotEmpty) {
    writeTag(7, 2);
    final b = utf8.encode(sourceLabel);
    out.add(sushiUvarint(b.length));
    out.add(b);
  }
  return out.toBytes();
}

/// Encodes a `sushi.v1.SubtitleFileReq`: field 1 `tag` (string).
Uint8List sushiEncodeSubtitleFileReq({required String tag}) {
  final out = BytesBuilder();
  if (tag.isNotEmpty) {
    out.add(sushiUvarint((1 << 3) | 2));
    final b = utf8.encode(tag);
    out.add(sushiUvarint(b.length));
    out.add(b);
  }
  return out.toBytes();
}
