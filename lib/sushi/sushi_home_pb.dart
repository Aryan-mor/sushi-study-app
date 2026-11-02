import 'dart:convert';
import 'dart:typed_data';

import 'package:fladder/sushi/sushi_app_update_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

/// Hand-decode/encode of `sushi.v1.HomeReq`/`HomeRes`/`Rail`/`Row`
/// (proto/sushi/v1/home.proto, proto/sushi/v1/catalog.proto), same style as
/// `sushi_assignment_pb.dart`'s `SushiAssignmentPb`.

const sushiHomeTabMovies = 1;
const sushiHomeTabSeries = 2;

/// Mirrors `sushi.v1.Kind`.
enum SushiKind { unspecified, movie, series }

SushiKind sushiKindFromWire(int v) => switch (v) {
      1 => SushiKind.movie,
      2 => SushiKind.series,
      _ => SushiKind.unspecified,
    };

int sushiKindToWire(SushiKind k) => switch (k) {
      SushiKind.movie => 1,
      SushiKind.series => 2,
      SushiKind.unspecified => 0,
    };

/// Mirrors `sushi.v1.RailKind`.
enum SushiRailKind { unspecified, slider, mostWatched, trending }

SushiRailKind sushiRailKindFromWire(int v) => switch (v) {
      1 => SushiRailKind.slider,
      2 => SushiRailKind.mostWatched,
      3 => SushiRailKind.trending,
      _ => SushiRailKind.unspecified,
    };

int sushiRailKindToWire(SushiRailKind k) => switch (k) {
      SushiRailKind.slider => 1,
      SushiRailKind.mostWatched => 2,
      SushiRailKind.trending => 3,
      SushiRailKind.unspecified => 0,
    };

/// One card, decoded from `sushi.v1.Row`.
class SushiRow {
  const SushiRow({
    required this.tmdbId,
    required this.kind,
    required this.title,
    required this.year,
    required this.rating,
    required this.poster,
  });

  final int tmdbId;
  final SushiKind kind;
  final String title;
  final int year;
  final int rating;
  final String poster;

  static SushiRow decode(Uint8List bytes) {
    var tmdbId = 0;
    var kind = 0;
    var title = '';
    var year = 0;
    var rating = 0;
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
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          kind = v.value;
        case 3:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          title = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 4:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          year = v.value;
        case 5:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          rating = v.value;
        case 6:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          poster = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiRow(tmdbId: tmdbId, kind: sushiKindFromWire(kind), title: title, year: year, rating: rating, poster: poster);
  }

  Map<String, Object?> toJson() => {
        'tmdbId': tmdbId,
        'kind': sushiKindToWire(kind),
        'title': title,
        'year': year,
        'rating': rating,
        'poster': poster,
      };

  static SushiRow fromJson(Map<String, dynamic> json) {
    return SushiRow(
      tmdbId: (json['tmdbId'] as num?)?.toInt() ?? 0,
      kind: sushiKindFromWire((json['kind'] as num?)?.toInt() ?? 0),
      title: json['title'] as String? ?? '',
      year: (json['year'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      poster: json['poster'] as String? ?? '',
    );
  }
}

/// One rail, decoded from `sushi.v1.Rail`.
class SushiRail {
  const SushiRail({required this.kind, required this.rows});

  final SushiRailKind kind;
  final List<SushiRow> rows;

  static SushiRail decode(Uint8List bytes) {
    var kind = 0;
    final rows = <SushiRow>[];
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
          kind = v.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          rows.add(SushiRow.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiRail(kind: sushiRailKindFromWire(kind), rows: List.unmodifiable(rows));
  }
}

/// Home fetch publishes the hidden set here. The provider installs the sink; transport stays free of Riverpod.
typedef SushiNotInterestedSink = void Function(List<SushiNotInterestedTitle> titles);

SushiNotInterestedSink? sushiNotInterestedSink;

/// One hidden Home card, decoded from `sushi.v1.NotInterestedTitle`.
class SushiNotInterestedTitle {
  const SushiNotInterestedTitle({required this.tmdbId, required this.kind});

  final int tmdbId;
  final SushiKind kind;

  static SushiNotInterestedTitle decode(Uint8List bytes) {
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
    return SushiNotInterestedTitle(tmdbId: tmdbId, kind: sushiKindFromWire(kind));
  }
}

class SushiHomeRes {
  const SushiHomeRes({
    required this.rails,
    required this.seq,
    required this.ttlSeconds,
    this.latestApp,
    this.notInterested = const [],
  });

  final List<SushiRail> rails;
  final int seq;
  final int ttlSeconds;
  final SushiLatestApp? latestApp;
  final List<SushiNotInterestedTitle> notInterested;

  static SushiHomeRes decode(Uint8List bytes) {
    final rails = <SushiRail>[];
    var seq = 0;
    var ttlSeconds = 0;
    SushiLatestApp? latestApp;
    final notInterested = <SushiNotInterestedTitle>[];
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
          rails.add(SushiRail.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          seq = v.value;
        case 3:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          ttlSeconds = v.value;
        case 4:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          latestApp = SushiLatestApp.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 5:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          notInterested.add(SushiNotInterestedTitle.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiHomeRes(
      rails: List.unmodifiable(rails),
      seq: seq,
      ttlSeconds: ttlSeconds,
      latestApp: latestApp,
      notInterested: List.unmodifiable(notInterested),
    );
  }

  /// The rows of the first rail matching [kind], or an empty list if the server didn't send one.
  List<SushiRow> rowsFor(SushiRailKind kind) {
    for (final rail in rails) {
      if (rail.kind == kind) return rail.rows;
    }
    return const [];
  }
}

/// Encodes a `sushi.v1.HomeReq`: field 1 `tab`, field 2 `since_seq`, field 3 `platform`,
/// field 4 `current_version`.
Uint8List sushiEncodeHomeReq({
  required int tab,
  int sinceSeq = 0,
  String platform = '',
  String currentVersion = '',
}) {
  final out = BytesBuilder();
  void writeTag(int field, int wire) => out.add(sushiUvarint((field << 3) | wire));
  if (tab != 0) {
    writeTag(1, 0);
    out.add(sushiUvarint(tab));
  }
  if (sinceSeq != 0) {
    writeTag(2, 0);
    out.add(sushiUvarint(sinceSeq));
  }
  if (platform.isNotEmpty) {
    writeTag(3, 2);
    final bytes = utf8.encode(platform);
    out.add(sushiUvarint(bytes.length));
    out.add(bytes);
  }
  if (currentVersion.isNotEmpty) {
    writeTag(4, 2);
    final bytes = utf8.encode(currentVersion);
    out.add(sushiUvarint(bytes.length));
    out.add(bytes);
  }
  return out.toBytes();
}
