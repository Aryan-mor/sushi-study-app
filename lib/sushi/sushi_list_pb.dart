import 'dart:convert';
import 'dart:typed_data';

import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

/// Hand codecs for `sushi.v1.ListReq` / `ListRes` (ADR 0009).

enum SushiListScope {
  unspecified,
  movies,
  series,
  boxsets,
  favorites,
  later,
  playlists,
  playlist,
  forYou,
  boxset,
  // The caller's personal videos (ADR 0037): rows are empty, [SushiListRes.personalVideos] is set.
  myVideos,
}

enum SushiListSort { unspecified, name, year, rating, added, trending, mostWatched }

int _scopeWire(SushiListScope s) => switch (s) {
      SushiListScope.movies => 1,
      SushiListScope.series => 2,
      SushiListScope.boxsets => 3,
      SushiListScope.favorites => 4,
      SushiListScope.later => 5,
      SushiListScope.playlists => 6,
      SushiListScope.playlist => 7,
      SushiListScope.forYou => 8,
      SushiListScope.boxset => 9,
      SushiListScope.myVideos => 10,
      _ => 0,
    };

SushiListScope _scopeFromWire(int v) => switch (v) {
      1 => SushiListScope.movies,
      2 => SushiListScope.series,
      3 => SushiListScope.boxsets,
      4 => SushiListScope.favorites,
      5 => SushiListScope.later,
      6 => SushiListScope.playlists,
      7 => SushiListScope.playlist,
      8 => SushiListScope.forYou,
      9 => SushiListScope.boxset,
      10 => SushiListScope.myVideos,
      _ => SushiListScope.unspecified,
    };

int _sortWire(SushiListSort s) => switch (s) {
      SushiListSort.name => 1,
      SushiListSort.year => 2,
      SushiListSort.rating => 3,
      SushiListSort.added => 4,
      SushiListSort.trending => 5,
      SushiListSort.mostWatched => 6,
      _ => 0,
    };

class SushiPlaylistMeta {
  const SushiPlaylistMeta({required this.playlistId, required this.name, required this.itemCount});
  final int playlistId;
  final String name;
  final int itemCount;

  static SushiPlaylistMeta decode(Uint8List bytes) {
    var playlistId = 0;
    var name = '';
    var itemCount = 0;
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
          playlistId = v.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          name = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 3:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          itemCount = v.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiPlaylistMeta(playlistId: playlistId, name: name, itemCount: itemCount);
  }
}

class SushiBoxsetMeta {
  const SushiBoxsetMeta({
    required this.collectionId,
    required this.name,
    required this.poster,
    required this.itemCount,
  });
  final int collectionId;
  final String name;
  final String poster;
  final int itemCount;

  static SushiBoxsetMeta decode(Uint8List bytes) {
    var collectionId = 0;
    var name = '';
    var poster = '';
    var itemCount = 0;
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
          collectionId = v.value;
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
        case 4:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          itemCount = v.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiBoxsetMeta(collectionId: collectionId, name: name, poster: poster, itemCount: itemCount);
  }
}

class SushiListRes {
  const SushiListRes({
    required this.rows,
    required this.cursor,
    this.playlists = const [],
    this.boxsets = const [],
    this.personalVideos = const [],
  });
  final List<SushiRow> rows;
  final int cursor;
  final List<SushiPlaylistMeta> playlists;
  final List<SushiBoxsetMeta> boxsets;
  final List<SushiPersonalVideo> personalVideos;

  static SushiListRes decode(Uint8List bytes) {
    final rows = <SushiRow>[];
    var cursor = 0;
    final playlists = <SushiPlaylistMeta>[];
    final boxsets = <SushiBoxsetMeta>[];
    final personalVideos = <SushiPersonalVideo>[];
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
          rows.add(SushiRow.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          cursor = v.value;
        case 3:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          playlists.add(SushiPlaylistMeta.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 4:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          boxsets.add(SushiBoxsetMeta.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 5:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          personalVideos.add(SushiPersonalVideo.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiListRes(
      rows: List.unmodifiable(rows),
      cursor: cursor,
      playlists: List.unmodifiable(playlists),
      boxsets: List.unmodifiable(boxsets),
      personalVideos: List.unmodifiable(personalVideos),
    );
  }
}

/// One `sushi.v1.PersonalVideo`: a card in My videos (ADR 0037). No thumbnail on the wire — the
/// app takes it from the delivered message the first time the video plays.
class SushiPersonalVideo {
  const SushiPersonalVideo({
    required this.personalId,
    required this.title,
    this.durationS = 0,
    this.sizeBytes = 0,
    this.positionS = 0,
    this.done = false,
  });

  final int personalId;

  /// This person's own name for the file.
  final String title;
  final int durationS;
  final int sizeBytes;
  final int positionS;
  final bool done;

  static SushiPersonalVideo decode(Uint8List bytes) {
    var personalId = 0;
    var title = '';
    var durationS = 0;
    var sizeBytes = 0;
    var positionS = 0;
    var done = false;
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
          personalId = v.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          title = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 3:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          durationS = v.value;
        case 4:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          sizeBytes = v.value;
        case 5:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          positionS = v.value;
        case 6:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          done = v.value != 0;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiPersonalVideo(
      personalId: personalId,
      title: title,
      durationS: durationS,
      sizeBytes: sizeBytes,
      positionS: positionS,
      done: done,
    );
  }
}

Uint8List sushiEncodeListReq({
  required SushiListScope scope,
  SushiListSort sort = SushiListSort.name,
  bool sortDesc = false,
  String genre = '',
  int year = 0,
  String q = '',
  int cursor = 0,
  int playlistId = 0,
  int collectionId = 0,
}) {
  final out = BytesBuilder();
  void writeTag(int field, int wire) => out.add(sushiUvarint((field << 3) | wire));
  final sw = _scopeWire(scope);
  if (sw != 0) {
    writeTag(1, 0);
    out.add(sushiUvarint(sw));
  }
  final sortW = _sortWire(sort);
  if (sortW != 0) {
    writeTag(2, 0);
    out.add(sushiUvarint(sortW));
  }
  if (sortDesc) {
    writeTag(3, 0);
    out.add(sushiUvarint(1));
  }
  if (genre.isNotEmpty) {
    writeTag(4, 2);
    final b = utf8.encode(genre);
    out.add(sushiUvarint(b.length));
    out.add(b);
  }
  if (year != 0) {
    writeTag(5, 0);
    out.add(sushiUvarint(year));
  }
  if (q.isNotEmpty) {
    writeTag(6, 2);
    final b = utf8.encode(q);
    out.add(sushiUvarint(b.length));
    out.add(b);
  }
  if (cursor != 0) {
    writeTag(7, 0);
    out.add(sushiUvarint(cursor));
  }
  if (playlistId != 0) {
    writeTag(8, 0);
    out.add(sushiUvarint(playlistId));
  }
  if (collectionId != 0) {
    writeTag(9, 0);
    out.add(sushiUvarint(collectionId));
  }
  return out.toBytes();
}

// silence unused warning for scope decode helper used by tests later
SushiListScope sushiListScopeFromWire(int v) => _scopeFromWire(v);
