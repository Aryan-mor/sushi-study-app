import 'dart:convert';
import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

const _prefsKey = 'sushi_continue_v1';
const _maxItems = 10;

/// Continue-watching is client-owned (docs/12 §2) — never a home rail on the wire.
class SushiContinueEntry {
  const SushiContinueEntry({
    required this.tmdbId,
    required this.kind,
    required this.title,
    required this.year,
    required this.rating,
    required this.poster,
    required this.positionMs,
    required this.durationMs,
    required this.atMs,
    this.episodeItemId,
    this.season,
    this.episode,
  });

  final int tmdbId;
  final SushiKind kind;
  final String title;
  final int year;
  final int rating;
  final String poster;
  final int positionMs;
  final int durationMs;
  final int atMs;
  final String? episodeItemId;
  final int? season;
  final int? episode;

  double get progressPct {
    if (durationMs <= 0) return 0;
    return (positionMs / durationMs * 100).clamp(0, 100);
  }

  bool get isFinished => progressPct >= 90;
  bool get isStarted => durationMs <= 0 || progressPct >= 5;

  /// Mid-watch: started and not finished. These lead the continue-watching rail.
  bool get isInProgress => isStarted && !isFinished && durationMs > 0;

  SushiContinueEntry copyWith({
    int? positionMs,
    int? durationMs,
    int? atMs,
    String? episodeItemId,
    int? season,
    int? episode,
  }) {
    return SushiContinueEntry(
      tmdbId: tmdbId,
      kind: kind,
      title: title,
      year: year,
      rating: rating,
      poster: poster,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      atMs: atMs ?? this.atMs,
      episodeItemId: episodeItemId ?? this.episodeItemId,
      season: season ?? this.season,
      episode: episode ?? this.episode,
    );
  }

  Map<String, Object?> toJson() => {
        'tmdbId': tmdbId,
        'kind': kind == SushiKind.series ? 2 : 1,
        'title': title,
        'year': year,
        'rating': rating,
        'poster': poster,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'atMs': atMs,
        if (episodeItemId != null && episodeItemId!.isNotEmpty) 'episodeItemId': episodeItemId,
        if (season != null) 'season': season,
        if (episode != null) 'episode': episode,
      };

  static SushiContinueEntry? fromJson(Map<String, dynamic> json) {
    final tmdbId = json['tmdbId'] as int? ?? 0;
    if (tmdbId == 0) return null;
    return SushiContinueEntry(
      tmdbId: tmdbId,
      kind: json['kind'] == 2 ? SushiKind.series : SushiKind.movie,
      title: json['title'] as String? ?? '',
      year: json['year'] as int? ?? 0,
      rating: json['rating'] as int? ?? 0,
      poster: json['poster'] as String? ?? '',
      positionMs: json['positionMs'] as int? ?? 0,
      durationMs: json['durationMs'] as int? ?? 0,
      atMs: json['atMs'] as int? ?? 0,
      episodeItemId: json['episodeItemId'] as String?,
      season: json['season'] as int?,
      episode: json['episode'] as int?,
    );
  }

  ItemBaseModel toItem() {
    final row = SushiRow(
      tmdbId: tmdbId,
      kind: kind,
      title: title,
      year: year,
      rating: rating,
      poster: poster,
    );
    final ticks = positionMs * 10000;
    return sushiRowToItemBaseModel(row).copyWith(
      userData: UserData(
        playbackPositionTicks: ticks,
        progress: progressPct,
        lastPlayed: DateTime.fromMillisecondsSinceEpoch(atMs),
      ),
    );
  }
}

({int tmdbId, SushiKind kind, String title, int year, int rating, String poster})? sushiContinueIdentity(ItemBaseModel item) {
  if (item is EpisodeModel) {
    final tmdb = sushiTmdbIdFromItemId(item.parentId ?? '');
    if (tmdb == null) return null;
    return (
      tmdbId: tmdb,
      kind: SushiKind.series,
      title: item.seriesName?.isNotEmpty == true ? item.seriesName! : item.name,
      year: item.overview.yearAired ?? 0,
      rating: ((item.overview.communityRating ?? 0) * 10).round(),
      poster: sushiPosterKeyFromImageUrl(item.images?.primary?.path ?? item.parentImages?.primary?.path ?? ''),
    );
  }
  final tmdb = sushiTmdbIdFromItemId(item.id);
  if (tmdb == null) return null;
  return (
    tmdbId: tmdb,
    kind: item is SeriesModel ? SushiKind.series : SushiKind.movie,
    title: item.name,
    year: item.overview.yearAired ?? 0,
    rating: ((item.overview.communityRating ?? 0) * 10).round(),
    poster: sushiPosterKeyFromImageUrl(item.images?.primary?.path ?? ''),
  );
}

String sushiPosterKeyFromImageUrl(String path) {
  if (path.isEmpty) return '';
  final file = path.split('/').last;
  return file.replaceAll(RegExp(r'\.(jpg|jpeg|png|webp)$', caseSensitive: false), '');
}

SushiContinueEntry? sushiContinueEntryFromItem(
  ItemBaseModel item, {
  required Duration position,
  required Duration duration,
}) {
  final id = sushiContinueIdentity(item);
  if (id == null) return null;
  return SushiContinueEntry(
    tmdbId: id.tmdbId,
    kind: id.kind,
    title: id.title,
    year: id.year,
    rating: id.rating,
    poster: id.poster,
    positionMs: position.inMilliseconds,
    durationMs: duration.inMilliseconds,
    atMs: DateTime.now().millisecondsSinceEpoch,
    episodeItemId: item is EpisodeModel ? item.id : null,
    season: item is EpisodeModel ? item.season : null,
    episode: item is EpisodeModel ? item.episode : null,
  );
}

/// Series stay in continue-watching until every episode is finished.
/// A <5% bounce (next/prev skip, immediate Back) must not wipe an in-progress row.
/// A finished episode with [nextEpisode] becomes that next episode at 0%. When the live
/// playback queue has no successor, stay on the episode just finished. Inventing
/// "same season, episode + 1" points Play at a number the catalog does not have.
SushiContinueEntry? sushiContinueRememberDecision({
  required SushiContinueEntry incoming,
  SushiContinueEntry? existing,
  SushiContinueEntry? nextEpisode,
}) {
  if (incoming.kind != SushiKind.series) {
    if (!incoming.isFinished && incoming.isStarted) return incoming;
    return null;
  }
  final durationKnown = incoming.durationMs > 0;
  if (durationKnown && incoming.isFinished) {
    return nextEpisode ?? incoming;
  }
  if (durationKnown && incoming.isStarted) {
    return incoming;
  }
  return existing ?? incoming;
}

Future<void> sushiContinueRemember(
  ItemBaseModel item,
  Duration position,
  Duration duration, {
  ItemBaseModel? nextItem,
}) async {
  final entry = sushiContinueEntryFromItem(item, position: position, duration: duration);
  if (entry == null) {
    log('[sushi-progress] sushiContinueRemember item=${item.id} position=$position '
        'duration=$duration entry=null (no tmdb identity — nothing to persist)');
    return;
  }
  log('[sushi-progress] sushiContinueRemember item=${item.id} position=$position '
      'duration=$duration title=${entry.title} progressPct=${entry.progressPct} '
      'isStarted=${entry.isStarted} isFinished=${entry.isFinished}');
  final existing = await _readAll();
  SushiContinueEntry? previous;
  for (final e in existing) {
    if (e.tmdbId == entry.tmdbId && e.kind == entry.kind) {
      previous = e;
      break;
    }
  }
  SushiContinueEntry? nextEntry;
  if (nextItem is EpisodeModel && sushiContinueIdentity(nextItem) != null) {
    nextEntry = sushiContinueEntryFromItem(
      nextItem,
      position: Duration.zero,
      duration: Duration.zero,
    );
  }
  final keep = sushiContinueRememberDecision(
    incoming: entry,
    existing: previous,
    nextEpisode: nextEntry,
  );
  if (keep == null) {
    log('[sushi-progress] sushiContinueRemember decision: DISCARDED — nothing persisted '
        '(previous entry progressPct=${previous?.progressPct})');
  } else {
    log('[sushi-progress] sushiContinueRemember decision: keeping title=${keep.title} '
        'progressPct=${keep.progressPct} episodeItemId=${keep.episodeItemId} '
        '(previous entry progressPct=${previous?.progressPct})');
  }
  final next = [
    if (keep != null) keep.copyWith(atMs: DateTime.now().millisecondsSinceEpoch),
    ...existing.where((e) => e.tmdbId != entry.tmdbId || e.kind != entry.kind),
  ];
  await _writeAll(next.take(_maxItems).toList());
  log('[sushi-progress] sushiContinueRemember wrote ${next.length} entries to prefs');
}

/// Menu-driven "Add to Continue Watching" (poster overflow menu on the home rows). Unlike
/// [sushiContinueRemember] — which is playback telling the store where the user stopped — this
/// just pins the title to the top of the rail at 0% progress. Re-adding an existing title moves
/// it to the top and resets its progress.
Future<void> sushiContinueAdd(ItemBaseModel item) async {
  final id = sushiContinueIdentity(item);
  if (id == null) return;
  final entry = SushiContinueEntry(
    tmdbId: id.tmdbId,
    kind: id.kind,
    title: id.title,
    year: id.year,
    rating: id.rating,
    poster: id.poster,
    positionMs: 0,
    durationMs: 0,
    atMs: DateTime.now().millisecondsSinceEpoch,
  );
  final existing = await _readAll();
  final next = [
    entry,
    ...existing.where((e) => e.tmdbId != entry.tmdbId || e.kind != entry.kind),
  ];
  await _writeAll(next.take(_maxItems).toList());
}

/// Menu-driven "Remove from Continue Watching" — drops the matching entry, if any.
Future<void> sushiContinueForget(ItemBaseModel item) async {
  final id = sushiContinueIdentity(item);
  if (id == null) return;
  final existing = await _readAll();
  final next = existing.where((e) => e.tmdbId != id.tmdbId || e.kind != id.kind).toList();
  if (next.length == existing.length) return;
  await _writeAll(next);
}

/// Drop a continue row whose resume target is this episode (mark-as-watched).
Future<void> sushiContinueForgetEpisode(String episodeItemId) async {
  if (episodeItemId.isEmpty) return;
  final existing = await _readAll();
  final next = existing.where((e) => e.episodeItemId != episodeItemId).toList();
  if (next.length == existing.length) return;
  await _writeAll(next);
}

/// In-progress first (newest activity first), then the rest newest→oldest.
List<SushiContinueEntry> sushiContinueSortEntries(Iterable<SushiContinueEntry> entries) {
  final list = entries.toList();
  int rank(SushiContinueEntry e) => e.isInProgress ? 0 : 1;
  list.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    return b.atMs.compareTo(a.atMs);
  });
  return list;
}

Future<List<ItemBaseModel>> sushiContinueLoad() async {
  final entries = sushiContinueSortEntries(await _readAll());
  return [for (final e in entries) e.toItem()];
}

Future<SushiContinueEntry?> sushiContinueFind({
  required int tmdbId,
  required SushiKind kind,
}) async {
  final entries = await _readAll();
  for (final entry in entries) {
    if (entry.tmdbId == tmdbId && entry.kind == kind) return entry;
  }
  return null;
}

Future<List<SushiContinueEntry>> _readAll() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_prefsKey);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return [
      for (final row in list)
        if (SushiContinueEntry.fromJson(Map<String, dynamic>.from(row as Map)) case final e?) e,
    ];
  } catch (_) {
    return const [];
  }
}

Future<void> _writeAll(List<SushiContinueEntry> entries) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsKey, jsonEncode([for (final e in entries) e.toJson()]));
}
