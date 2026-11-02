import 'dart:convert';
import 'dart:typed_data';

import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

/// Hand codecs for `sushi.v1.TasteReq` / `TasteRes` / `TasteTitle` / `TastePerson`.

class SushiTasteTitle {
  const SushiTasteTitle({required this.tmdbId, required this.kind});

  final int tmdbId;
  final int kind; // 1 movie, 2 series

  Uint8List encode() {
    final out = BytesBuilder();
    if (tmdbId != 0) {
      out.add(sushiUvarint((1 << 3) | 0));
      out.add(sushiUvarint(tmdbId));
    }
    if (kind != 0) {
      out.add(sushiUvarint((2 << 3) | 0));
      out.add(sushiUvarint(kind));
    }
    return out.toBytes();
  }

  static SushiTasteTitle decode(Uint8List bytes) {
    var tmdbId = 0;
    var kind = 0;
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
          tmdbId = v.value;
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          kind = v.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiTasteTitle(tmdbId: tmdbId, kind: kind);
  }
}

class SushiTastePerson {
  const SushiTastePerson({
    required this.tmdbId,
    required this.name,
    this.poster = '',
  });

  final int tmdbId;
  final String name;
  final String poster;

  static SushiTastePerson decode(Uint8List bytes) {
    var tmdbId = 0;
    var name = '';
    var poster = '';
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
          tmdbId = v.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          name = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 3:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          poster = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiTastePerson(tmdbId: tmdbId, name: name, poster: poster);
  }
}

class SushiTasteRes {
  const SushiTasteRes({
    this.complete = false,
    this.watchKind = '',
    this.genres = const [],
    this.likedTitles = const [],
    this.likedPeople = const [],
    this.maxHeight = 0,
    this.audio = '',
    this.subtitleLang = '',
    this.subs = '',
    this.seedTitles = const [],
    this.seedPeople = const [],
    this.personHits = const [],
  });

  final bool complete;
  final String watchKind;
  final List<String> genres;
  final List<SushiTasteTitle> likedTitles;
  final List<int> likedPeople;
  final int maxHeight;
  final String audio;
  final String subtitleLang;
  final String subs;
  final List<SushiRow> seedTitles;
  final List<SushiTastePerson> seedPeople;
  final List<SushiTastePerson> personHits;

  static SushiTasteRes decode(Uint8List bytes) {
    var complete = false;
    var watchKind = '';
    final genres = <String>[];
    final likedTitles = <SushiTasteTitle>[];
    final likedPeople = <int>[];
    var maxHeight = 0;
    var audio = '';
    var subtitleLang = '';
    var subs = '';
    final seedTitles = <SushiRow>[];
    final seedPeople = <SushiTastePerson>[];
    final personHits = <SushiTastePerson>[];
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
          complete = v.value != 0;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          watchKind = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 3:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          genres.add(utf8.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 4:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          likedTitles.add(SushiTasteTitle.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 5:
          // proto3 packs repeated uint64 → wire type 2; also accept unpacked varints.
          if (wire == 2) {
            final lenR = sushiReadVarint(bytes, i);
            i = lenR.next;
            final end = i + lenR.value;
            while (i < end) {
              final v = sushiReadVarint(bytes, i);
              i = v.next;
              likedPeople.add(v.value);
            }
          } else {
            final v = sushiReadVarint(bytes, i);
            i = v.next;
            likedPeople.add(v.value);
          }
        case 6:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          maxHeight = v.value;
        case 7:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          audio = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 8:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          subtitleLang = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 9:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          seedTitles.add(SushiRow.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 10:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          seedPeople.add(SushiTastePerson.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 11:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          personHits.add(SushiTastePerson.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 12:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          subs = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiTasteRes(
      complete: complete,
      watchKind: watchKind,
      genres: List.unmodifiable(genres),
      likedTitles: List.unmodifiable(likedTitles),
      likedPeople: List.unmodifiable(likedPeople),
      maxHeight: maxHeight,
      audio: audio,
      subtitleLang: subtitleLang,
      subs: subs,
      seedTitles: List.unmodifiable(seedTitles),
      seedPeople: List.unmodifiable(seedPeople),
      personHits: List.unmodifiable(personHits),
    );
  }
}

Uint8List sushiEncodeTasteReq({
  bool write = false,
  String watchKind = '',
  List<String> genres = const [],
  List<SushiTasteTitle> likedTitles = const [],
  List<int> likedPeople = const [],
  int maxHeight = 0,
  String audio = '',
  String subtitleLang = '',
  String subs = '',
  String personQuery = '',
  int seedPage = 0,
  int personSeedPage = 0,
}) {
  final out = BytesBuilder();
  void writeTag(int field, int wire) => out.add(sushiUvarint((field << 3) | wire));
  void writeString(int field, String s) {
    if (s.isEmpty) return;
    writeTag(field, 2);
    final b = utf8.encode(s);
    out.add(sushiUvarint(b.length));
    out.add(b);
  }

  if (write) {
    writeTag(1, 0);
    out.add(sushiUvarint(1));
  }
  writeString(2, watchKind);
  for (final g in genres) {
    writeString(3, g);
  }
  for (final t in likedTitles) {
    final enc = t.encode();
    writeTag(4, 2);
    out.add(sushiUvarint(enc.length));
    out.add(enc);
  }
  for (final id in likedPeople) {
    if (id == 0) continue;
    writeTag(5, 0);
    out.add(sushiUvarint(id));
  }
  if (maxHeight != 0) {
    writeTag(6, 0);
    out.add(sushiUvarint(maxHeight));
  }
  writeString(7, audio);
  writeString(8, subtitleLang);
  writeString(9, personQuery);
  writeString(12, subs);
  if (seedPage > 0) {
    writeTag(10, 0);
    out.add(sushiUvarint(seedPage));
  }
  if (personSeedPage > 0) {
    writeTag(11, 0);
    out.add(sushiUvarint(personSeedPage));
  }
  return out.toBytes();
}
