import 'dart:convert';
import 'dart:typed_data';

import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

/// Hand-decode/encode of `sushi.v1.ItemReq`/`ItemRes`/`FilesReq`/`FilesRes`/`Episode`/`File`
/// (proto/sushi/v1/item.proto, proto/sushi/v1/catalog.proto) — opening a title (docs/12 §4) and
/// its pick-list (docs/12 §5). Same style as sushi_home_pb.dart.

/// Mirrors `sushi.v1.FileState`.
enum SushiFileState { unspecified, ready, pending, unavailable }

SushiFileState sushiFileStateFromWire(int v) => switch (v) {
      1 => SushiFileState.ready,
      2 => SushiFileState.pending,
      3 => SushiFileState.unavailable,
      _ => SushiFileState.unspecified,
    };

int sushiFileStateToWire(SushiFileState s) => switch (s) {
      SushiFileState.ready => 1,
      SushiFileState.pending => 2,
      SushiFileState.unavailable => 3,
      SushiFileState.unspecified => 0,
    };

/// One entry of a title's season/episode tree. A movie gets exactly one, season 0 episode 0
/// (catalog.proto's convention) — the id `files()` is keyed on, movie or series alike.
class SushiEpisode {
  const SushiEpisode({
    required this.episodeId,
    required this.seasonNo,
    required this.episodeNo,
    required this.title,
  });

  final int episodeId;
  final int seasonNo;
  final int episodeNo;
  final String title;

  static SushiEpisode decode(Uint8List bytes) {
    var episodeId = 0;
    var seasonNo = 0;
    var episodeNo = 0;
    var title = '';
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
          episodeId = v.value;
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          seasonNo = v.value;
        case 3:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          episodeNo = v.value;
        case 4:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          title = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiEpisode(episodeId: episodeId, seasonNo: seasonNo, episodeNo: episodeNo, title: title);
  }

  Map<String, Object?> toJson() => {
        'episodeId': episodeId,
        'seasonNo': seasonNo,
        'episodeNo': episodeNo,
        'title': title,
      };

  static SushiEpisode fromJson(Map<String, dynamic> json) {
    return SushiEpisode(
      episodeId: (json['episodeId'] as num?)?.toInt() ?? 0,
      seasonNo: (json['seasonNo'] as num?)?.toInt() ?? 0,
      episodeNo: (json['episodeNo'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
    );
  }
}

/// Index row on a series title page (ADR 0028). Episode bodies arrive via /episodes.
class SushiSeason {
  const SushiSeason({required this.seasonNo, required this.episodeCount});

  final int seasonNo;
  final int episodeCount;

  static SushiSeason decode(Uint8List bytes) {
    var seasonNo = 0;
    var episodeCount = 0;
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
          seasonNo = v.value;
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          episodeCount = v.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiSeason(seasonNo: seasonNo, episodeCount: episodeCount);
  }
}

/// One playable encoding of one episode (the pick-list, docs/12 §5).
class SushiFile {
  const SushiFile({
    required this.fileId,
    required this.qualityLabel,
    required this.height,
    required this.audioLangs,
    required this.subLangs,
    required this.sizeBytes,
    required this.durationS,
    required this.state,
    this.displayName = '',
  });

  final int fileId;
  final String qualityLabel;
  final int height;
  final String audioLangs;
  final String subLangs;
  final int sizeBytes;
  final int durationS;
  final SushiFileState state;

  /// Admin-set file label. Empty means [qualityLabel] is the name the picker shows.
  final String displayName;

  static SushiFile decode(Uint8List bytes) {
    var fileId = 0;
    var qualityLabel = '';
    var height = 0;
    var audioLangs = '';
    var subLangs = '';
    var sizeBytes = 0;
    var durationS = 0;
    var state = 0;
    var displayName = '';
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
          fileId = v.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          qualityLabel = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 3:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          height = v.value;
        case 4:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          audioLangs = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 5:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          subLangs = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 6:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          sizeBytes = v.value;
        case 7:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          durationS = v.value;
        case 8:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          state = v.value;
        case 9:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          displayName = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiFile(
      fileId: fileId,
      qualityLabel: qualityLabel,
      height: height,
      audioLangs: audioLangs,
      subLangs: subLangs,
      sizeBytes: sizeBytes,
      durationS: durationS,
      state: sushiFileStateFromWire(state),
      displayName: displayName,
    );
  }

  Map<String, Object?> toJson() => {
        'fileId': fileId,
        'qualityLabel': qualityLabel,
        'height': height,
        'audioLangs': audioLangs,
        'subLangs': subLangs,
        'sizeBytes': sizeBytes,
        'durationS': durationS,
        'state': sushiFileStateToWire(state),
        'displayName': displayName,
      };

  static SushiFile fromJson(Map<String, dynamic> json) {
    return SushiFile(
      fileId: (json['fileId'] as num?)?.toInt() ?? 0,
      qualityLabel: json['qualityLabel'] as String? ?? '',
      height: (json['height'] as num?)?.toInt() ?? 0,
      audioLangs: json['audioLangs'] as String? ?? '',
      subLangs: json['subLangs'] as String? ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      durationS: (json['durationS'] as num?)?.toInt() ?? 0,
      state: sushiFileStateFromWire((json['state'] as num?)?.toInt() ?? 0),
      displayName: json['displayName'] as String? ?? '',
    );
  }
}

class SushiPerson {
  const SushiPerson({required this.name, required this.role, required this.profile, this.tmdbId = 0});

  final String name;
  final String role;
  final String profile;
  final int tmdbId;

  static SushiPerson decode(Uint8List bytes) {
    var name = '';
    var role = '';
    var profile = '';
    var tmdbId = 0;
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
          name = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          role = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 3:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          profile = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 4:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          tmdbId = v.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiPerson(name: name, role: role, profile: profile, tmdbId: tmdbId);
  }
}

/// Decoded `sushi.v1.PersonRes`.
class SushiPersonRes {
  const SushiPersonRes({
    required this.tmdbId,
    required this.name,
    required this.profile,
    required this.biography,
    required this.movies,
    required this.series,
  });

  final int tmdbId;
  final String name;
  final String profile;
  final String biography;
  final List<SushiRow> movies;
  final List<SushiRow> series;

  static SushiPersonRes decode(Uint8List bytes) {
    var tmdbId = 0;
    var name = '';
    var profile = '';
    var biography = '';
    final movies = <SushiRow>[];
    final series = <SushiRow>[];
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
          profile = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 4:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          biography = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 5:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          movies.add(SushiRow.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 6:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          series.add(SushiRow.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiPersonRes(
      tmdbId: tmdbId,
      name: name,
      profile: profile,
      biography: biography,
      movies: List.unmodifiable(movies),
      series: List.unmodifiable(series),
    );
  }
}

Uint8List sushiEncodePersonReq({required int tmdbId}) {
  final out = BytesBuilder();
  if (tmdbId != 0) {
    out.add(sushiUvarint((1 << 3) | 0));
    out.add(sushiUvarint(tmdbId));
  }
  return out.toBytes();
}

/// Decoded `sushi.v1.ItemRes` — the title page (docs/12 §4).
class SushiItemRes {
  const SushiItemRes({
    required this.row,
    required this.overview,
    required this.releasedOn,
    required this.episodes,
    this.logo = '',
    this.backdrop = '',
    this.genres = '',
    this.runtimeS = 0,
    this.people = const [],
    this.related = const [],
    this.collectionName = '',
    this.collection = const [],
    this.seasons = const [],
    this.trailerKey = '',
    this.country = '',
    this.wire,
  });

  final SushiRow row;
  final String overview;
  final int releasedOn;
  final List<SushiEpisode> episodes;
  final String logo;
  final String backdrop;
  final String genres;
  final int runtimeS;
  final List<SushiPerson> people;
  final List<SushiRow> related;
  final String collectionName;
  final List<SushiRow> collection;
  final List<SushiSeason> seasons;
  /// YouTube video id for the trailer button (docs/12 §4, ADR 0031). Empty means none.
  final String trailerKey;
  /// ISO 3166-1 alpha-2 origin country. Empty means unknown.
  final String country;
  /// Original protobuf bytes. Needed to persist a title page without a Dart encoder.
  final Uint8List? wire;

  static SushiItemRes decode(Uint8List bytes) {
    SushiRow row = const SushiRow(tmdbId: 0, kind: SushiKind.unspecified, title: '', year: 0, rating: 0, poster: '');
    var overview = '';
    var releasedOn = 0;
    final episodes = <SushiEpisode>[];
    var logo = '';
    var backdrop = '';
    var genres = '';
    var runtimeS = 0;
    final people = <SushiPerson>[];
    final related = <SushiRow>[];
    var collectionName = '';
    final collection = <SushiRow>[];
    final seasons = <SushiSeason>[];
    var trailerKey = '';
    var country = '';
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
          row = SushiRow.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          overview = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 3:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          releasedOn = v.value;
        case 4:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          episodes.add(SushiEpisode.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 5:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          logo = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 6:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          backdrop = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 7:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          genres = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 8:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          runtimeS = v.value;
        case 9:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          people.add(SushiPerson.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 10:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          related.add(SushiRow.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 11:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          collectionName = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 12:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          collection.add(SushiRow.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 15:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          seasons.add(SushiSeason.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 16:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          trailerKey = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 17:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          country = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiItemRes(
      row: row,
      overview: overview,
      releasedOn: releasedOn,
      episodes: List.unmodifiable(episodes),
      logo: logo,
      backdrop: backdrop,
      genres: genres,
      runtimeS: runtimeS,
      people: List.unmodifiable(people),
      related: List.unmodifiable(related),
      collectionName: collectionName,
      collection: List.unmodifiable(collection),
      seasons: List.unmodifiable(seasons),
      trailerKey: trailerKey,
      country: country,
      wire: bytes,
    );
  }
}

/// Decoded `sushi.v1.FilesRes`.
class SushiFilesRes {
  const SushiFilesRes({
    required this.files,
    this.positionS = 0,
    this.done = false,
    this.lastFileId = 0,
    this.known = true,
  });

  final List<SushiFile> files;
  final int positionS;
  final bool done;
  final int lastFileId;

  /// False only when neither the network nor the file cache produced a list. An empty
  /// [files] with [known] true means the server said there is nothing to play.
  final bool known;

  bool get hasProgress => done || positionS > 0;

  int get resumeDurationS {
    if (lastFileId != 0) {
      for (final f in files) {
        if (f.fileId == lastFileId && f.durationS > 0) return f.durationS;
      }
    }
    for (final f in files) {
      if (f.durationS > 0) return f.durationS;
    }
    return 0;
  }

  static SushiFilesRes decode(Uint8List bytes) {
    final files = <SushiFile>[];
    var positionS = 0;
    var done = false;
    var lastFileId = 0;
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
          files.add(SushiFile.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          positionS = v.value;
        case 3:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          done = v.value != 0;
        case 4:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          lastFileId = v.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiFilesRes(
      files: List.unmodifiable(files),
      positionS: positionS,
      done: done,
      lastFileId: lastFileId,
    );
  }
}

/// Encodes a `sushi.v1.ItemReq`: field 1 `tmdb_id` (varint), field 2 `kind` (varint enum).
Uint8List sushiEncodeItemReq({required int tmdbId, required int kind}) {
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
  return out.toBytes();
}

/// Encodes a `sushi.v1.FilesReq`: field 1 `episode_id` (varint).
Uint8List sushiEncodeFilesReq({required int episodeId}) {
  final out = BytesBuilder();
  if (episodeId != 0) {
    out.add(sushiUvarint((1 << 3) | 0));
    out.add(sushiUvarint(episodeId));
  }
  return out.toBytes();
}

/// Encodes a `sushi.v1.EpisodesReq`.
Uint8List sushiEncodeEpisodesReq({
  required int tmdbId,
  required int kind,
  required int seasonNo,
  int page = 0,
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
  if (page != 0) {
    writeTag(4, 0);
    out.add(sushiUvarint(page));
  }
  return out.toBytes();
}

/// Decoded `sushi.v1.EpisodesRes`.
class SushiEpisodesRes {
  const SushiEpisodesRes({
    required this.episodes,
    this.page = 0,
    this.pages = 0,
  });

  final List<SushiEpisode> episodes;
  final int page;
  final int pages;

  static SushiEpisodesRes decode(Uint8List bytes) {
    final episodes = <SushiEpisode>[];
    var page = 0;
    var pages = 0;
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
          episodes.add(SushiEpisode.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          page = v.value;
        case 3:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          pages = v.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiEpisodesRes(
      episodes: List.unmodifiable(episodes),
      page: page,
      pages: pages,
    );
  }
}

/// Playable catalog title: a movie episode id, or a series with a season index (ADR 0028).
bool sushiItemResPlayable(SushiItemRes page) {
  if (page.episodes.any((e) => e.episodeId != 0)) return true;
  return page.seasons.any((s) => s.episodeCount > 0);
}
