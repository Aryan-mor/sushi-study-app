import 'package:collection/collection.dart';

import 'package:fladder/jellyfin/enum_models.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/person_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_account_playback_pref.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_playback_subtitle.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_media_variant.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

/// File duration from `/files`, preferring [lastFileId]. Zero means unknown.
Duration? sushiRunTimeFromFiles(List<SushiFile> files, {int lastFileId = 0}) {
  final durationS = SushiFilesRes(files: files, lastFileId: lastFileId).resumeDurationS;
  if (durationS <= 0) return null;
  return Duration(seconds: durationS);
}

OverviewModel sushiOverviewWithFileRunTime(
  OverviewModel overview,
  List<SushiFile> files, {
  int lastFileId = 0,
}) {
  final runTime = sushiRunTimeFromFiles(files, lastFileId: lastFileId);
  if (runTime == null) return overview;
  return overview.copyWith(runTime: runTime);
}

const _sushiFileIdPrefix = 'sushi_file_';
const _sushiEpisodeIdPrefix = 'sushi_ep_';
const _sushiSeasonIdPrefix = 'sushi_season_';

/// Recovers the file id from a [VersionStreamModel.id] built by [sushiBuildMediaStreams] — the
/// reverse of that id's `'sushi_file_$fileId'`, needed once the user has picked a quality and
/// pressed play (docs/05 §3's `/play <fileId>`).
int? sushiFileIdFromVersionStreamId(String? versionStreamId) {
  if (versionStreamId == null || !versionStreamId.startsWith(_sushiFileIdPrefix)) return null;
  return int.tryParse(versionStreamId.substring(_sushiFileIdPrefix.length));
}

/// Local offline filename Fladder's SyncedItem.videoFile uses. Encodes the Sushi file id so a later
/// tap on "download again" can recover it from data.json without another `/files`.
String sushiOfflineFileName(int fileId) => '$_sushiFileIdPrefix$fileId.mkv';

int? sushiFileIdFromOfflineName(String? name) {
  if (name == null || name.isEmpty) return null;
  final match = RegExp(r'^sushi_file_(\d+)\.').firstMatch(name);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// Index of [codes] matching [preferred] (ISO 639-1 / common aliases), else 0.
/// Empty [preferred] or empty [codes] → 0.
int sushiPickPreferredLangIndex(List<String> codes, String preferred) {
  if (codes.isEmpty) return 0;
  final want = preferred.trim().toLowerCase();
  if (want.isEmpty) return 0;
  for (var i = 0; i < codes.length; i++) {
    if (sushiSubtitleLangMatches(codes[i], want)) return i;
  }
  return 0;
}

/// Drops hardsub / dub when the user chose a non-Persian subtitle language.
/// Softsub files stay — muxed tracks don't burn in; wrong-lang soft stays Off and
/// online/AI fills the preferred language. Persian (or unset) keeps the full list.
List<SushiFile> sushiFilterFilesForSubtitlePref(
  Iterable<SushiFile> files,
  SushiAccountPlaybackPref account,
) {
  if (account.wantsPersianSubtitles) {
    return files.toList();
  }
  return [
    for (final file in files)
      if (_sushiFileAllowedForNonPersianSubs(file)) file,
  ];
}

bool _sushiFileAllowedForNonPersianSubs(SushiFile file) {
  final subCodes = file.subLangs.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final delivery = sushiClassifyDeliveryLabel(
    file.qualityLabel,
    hasCatalogSubs: subCodes.isNotEmpty,
  );
  if (delivery == SushiStreamDelivery.hardSub) return false;
  if (delivery == SushiStreamDelivery.dubbed) return false;
  // Softsub / original / unknown: keep. Soft tracks are filtered to the account
  // lang in [sushiBuildMediaStreams]; no match → default Off → online/AI.
  return true;
}

SushiFile? sushiPickReadyFile(List<SushiFile> files, {String? versionStreamId}) {
  final ready = files.where((f) => f.state == SushiFileState.ready).toList();
  if (ready.isEmpty) return null;
  final wanted = sushiFileIdFromVersionStreamId(versionStreamId);
  if (wanted != null) {
    for (final file in ready) {
      if (file.fileId == wanted) return file;
    }
  }
  return ready.first;
}

int? sushiEpisodeIdFromItemId(String itemId) {
  if (!itemId.startsWith(_sushiEpisodeIdPrefix)) return null;
  return int.tryParse(itemId.substring(_sushiEpisodeIdPrefix.length));
}

String sushiEpisodeItemId(int episodeId) => '$_sushiEpisodeIdPrefix$episodeId';

/// Builds the [MediaStreamsModel] Fladder's play button / quality picker read
/// (`sushiMovieHasPlayableMedia`/`sushiShowMediaStreamHelper` both just check
/// `versionStreams.isNotEmpty`) from Sushi's compact [SushiFile] pick-list. Each file becomes one
/// version/quality choice; `audio_langs`/`sub_langs` are comma-separated ISO 639-1 codes
/// (catalog.NormalizeLangs, docs/12 §5.1) — there is no richer per-track metadata on the wire, so
/// one synthetic audio/sub stream per language code is all there is to build.
///
/// Only `state == ready` files are offered — `pending`/`unavailable` have nothing to play yet.
MediaStreamsModel sushiBuildMediaStreams(
  List<SushiFile> files, {
  int? preferredFileId,
  SushiMediaVariantPreference? localPreference,
  SushiAccountPlaybackPref? account,
  bool lockPreferredFile = false,
}) {
  final accountPref = account ?? sushiAccountPlaybackPref;
  final ready = sushiFilterFilesForSubtitlePref(
    files.where((f) => f.state == SushiFileState.ready),
    accountPref,
  ).toList();
  ready.sort((a, b) {
    final ap = a.displayName.trim().isNotEmpty ? 0 : 1;
    final bp = b.displayName.trim().isNotEmpty ? 0 : 1;
    return ap.compareTo(bp);
  });
  if (ready.isEmpty) {
    return MediaStreamsModel(versionStreams: const []);
  }

  final versions = ready.mapIndexed((index, file) {
    final audioCodes = file.audioLangs.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    var subCodes = file.subLangs.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    // Matching lang wins. A Persian ask with no fa track still keeps en/und: those tags are
    // often a Persian soft sub, and playback sniffs the text before going online.
    var sniffOnly = false;
    if (accountPref.subtitleLang.isNotEmpty) {
      final matched = [
        for (final c in subCodes)
          if (sushiSubtitleLangMatches(c, accountPref.subtitleLang)) c,
      ];
      if (matched.isNotEmpty) {
        subCodes = matched;
      } else if (accountPref.wantsPersianSubtitles) {
        subCodes = [
          for (final c in subCodes)
            if (sushiSubtitleLanguageNeedsScriptSniff(c)) c,
        ];
        sniffOnly = subCodes.isNotEmpty;
      } else {
        subCodes = const [];
      }
    }
    final defaultAudio = sushiPickPreferredLangIndex(
      audioCodes,
      accountPref.audioForVersionPick == SushiAudioPref.dub ? 'fa' : '',
    );
    // "Without" stays Off. Non-Persian "with subtitles" stays Off until auto online lands.
    final holdSubOff = accountPref.wantsSubtitlesOff || accountPref.wantsAutoOnlineSubtitles;
    // Sniff candidates stay in the list but are not a confirmed language match, so version
    // ranking does not treat a lone `en` tag as Persian.
    final defaultSub = holdSubOff || sniffOnly
        ? -1
        : sushiPickPreferredLangIndex(subCodes, accountPref.subtitleLangOrFa);

    // Empty audio_langs means the catalog has no ISO codes, not that the file is
    // silent. AudioStreamModel.no() (index -1) is the picker "Off" sentinel —
    // stuffing it here makes libMPV/libMDK call setAudioTrack(no()) and mute
    // muxed audio. Synthesize a default track so both players keep aid=auto.
    final audioStreams = (audioCodes.isEmpty ? const [''] : audioCodes).mapIndexed((i, code) {
      final label = code.isEmpty ? 'Default' : code.toUpperCase();
      return AudioStreamModel(
        displayTitle: label,
        name: label,
        language: code,
        codec: '',
        channelLayout: '',
        sampleRate: null,
        channels: null,
        bitRate: null,
        bitDepth: null,
        profile: null,
        spatialFormat: null,
        isDefault: i == defaultAudio,
        isExternal: false,
        index: i,
      );
    }).toList();

    final subStreams = subCodes.mapIndexed((i, code) {
      return SubStreamModel(
        name: code.toUpperCase(),
        id: 'sushi_sub_${file.fileId}_$i',
        title: code.toUpperCase(),
        displayTitle: code.toUpperCase(),
        language: code,
        codec: '',
        isDefault: i == defaultSub,
        isExternal: false,
        index: i,
      );
    }).toList();

    final shown = file.displayName.trim().isNotEmpty ? file.displayName.trim() : file.qualityLabel;
    return VersionStreamModel(
      name: file.qualityLabel,
      displayName: file.displayName.trim(),
      index: index,
      id: 'sushi_file_${file.fileId}',
      defaultAudioStreamIndex: audioStreams.isEmpty ? -1 : defaultAudio,
      defaultSubStreamIndex: subStreams.isEmpty ? -1 : defaultSub,
      videoStreams: [
        VideoStreamModel(
          name: shown,
          codec: '',
          isDefault: true,
          isExternal: false,
          index: 0,
          videoDoViTitle: null,
          videoRangeType: null,
          bitRate: null,
          width: 0,
          height: file.height,
          frameRate: 24,
        ),
      ],
      audioStreams: audioStreams,
      subStreams: subStreams,
      sizeBytes: file.sizeBytes > 0 ? file.sizeBytes : null,
    );
  }).toList();

  // The viewer already picked this exact upload. Quality + delivery cannot tell two
  // "1080 hard sub" files apart, so the saved preference would otherwise reopen the first one.
  if (lockPreferredFile && preferredFileId != null && preferredFileId != 0) {
    final wanted = '$_sushiFileIdPrefix$preferredFileId';
    final locked = versions.indexWhere((v) => v.id == wanted);
    if (locked >= 0) {
      final picked = versions[locked];
      return MediaStreamsModel(
        versionStreamIndex: picked.index,
        defaultAudioStreamIndex: picked.defaultAudioStreamIndex,
        defaultSubStreamIndex: picked.defaultSubStreamIndex,
        versionStreams: versions,
      );
    }
  }

  // A locally remembered per-title pick (the user explicitly switched to it before) wins over
  // the server's last-played file, which wins over the account's onboarding answer
  // ("subtitles over dubbing", max quality) ranking the list.
  final hasPin = versions.any((v) => v.displayName.trim().isNotEmpty);
  var index = sushiFindVersionStreamIndexForPreference(versions, localPreference);
  if (index == null && !hasPin && preferredFileId != null && preferredFileId != 0) {
    final wanted = '$_sushiFileIdPrefix$preferredFileId';
    final i = versions.indexWhere((v) => v.id == wanted);
    if (i >= 0) index = versions[i].index;
  }
  index ??= sushiPickColdVersionStreamIndex(versions, account: accountPref);
  final picked = versions[index.clamp(0, versions.length - 1)];
  return MediaStreamsModel(
    versionStreamIndex: index,
    defaultAudioStreamIndex: picked.defaultAudioStreamIndex,
    defaultSubStreamIndex: picked.defaultSubStreamIndex,
    versionStreams: versions,
  );
}

/// Keeps a file the viewer already picked when a catalog refresh rebuilds the pick-list.
///
/// The saved preference is only quality + delivery. Two uploads that both read "1080 hard sub"
/// collapse to the first match, so a refresh that lands after the pick would put the old file back.
MovieModel sushiPreservePickedMovieFile(MovieModel built, MovieModel? live) {
  final liveId = sushiFileIdFromVersionStreamId(live?.mediaStreams.currentVersionStream?.id);
  final builtId = sushiFileIdFromVersionStreamId(built.mediaStreams.currentVersionStream?.id);
  if (live == null || liveId == null || liveId == 0 || liveId == builtId) return built;
  return built.copyWith(mediaStreams: live.mediaStreams);
}

/// Same as [sushiPreservePickedMovieFile] for each episode still on screen.
SeriesModel sushiPreservePickedFiles(SeriesModel built, SeriesModel? live) {
  final liveEpisodes = live?.availableEpisodes;
  final builtEpisodes = built.availableEpisodes;
  if (liveEpisodes == null || builtEpisodes == null) return built;
  final liveById = {for (final episode in liveEpisodes) episode.id: episode};
  var changed = false;
  final next = <EpisodeModel>[];
  for (final episode in builtEpisodes) {
    final previous = liveById[episode.id];
    final liveId = sushiFileIdFromVersionStreamId(previous?.mediaStreams.currentVersionStream?.id);
    final builtId = sushiFileIdFromVersionStreamId(episode.mediaStreams.currentVersionStream?.id);
    if (previous != null && liveId != null && liveId != 0 && liveId != builtId) {
      changed = true;
      next.add(episode.copyWith(mediaStreams: previous.mediaStreams));
    } else {
      next.add(episode);
    }
  }
  if (!changed) return built;
  return built.copyWith(availableEpisodes: next);
}

/// Poster + TMDB logo/backdrop for a title. Seasons/episodes copy this onto
/// [SeasonModel.parentImages] / [EpisodeModel.parentImages] — OverviewHeader on the season
/// screen reads `image.logo`, so building it after those lists leaves the logo empty.
ImagesData sushiTitleImages(String itemId, ImagesData? base, SushiItemRes item) {
  return ImagesData(
    primary: base?.primary ?? sushiTmdbImage(item.row.poster, key: itemId),
    // MediaHeader maxWidth 700 + BoxFit.contain; original PNG is 1–2s on first paint.
    logo: sushiTmdbImage(item.logo, key: '${itemId}_logo', size: sushiTmdbDetailSize, extension: 'png') ??
        base?.logo,
    backDrop: item.backdrop.isEmpty
        ? base?.backDrop
        : [sushiTmdbImage(item.backdrop, key: '${itemId}_bd', size: sushiTmdbDetailSize)!],
  );
}

/// Copy title-page logo/backdrop onto a home card. Home rows only have the poster (R-META-1);
/// Fladder's slider paints backdrop, so slider items pick this up from the cached `/item`.
ItemBaseModel sushiAttachTitleImages(ItemBaseModel item, SushiItemRes page) {
  final images = sushiTitleImages(item.id, item.images, page);
  return switch (item) {
    MovieModel m => m.copyWith(images: images),
    SeriesModel s => s.copyWith(images: images),
    EpisodeModel e => e.copyWith(images: images, parentImages: images),
    _ => item.copyWith(images: images),
  };
}

bool sushiHomeItemMatchesPage(ItemBaseModel item, SushiItemRes page) {
  final identity = sushiContinueIdentity(item);
  if (identity == null) return false;
  return identity.tmdbId == page.row.tmdbId && identity.kind == page.row.kind;
}

List<ItemBaseModel> sushiPatchHomeItemImages(List<ItemBaseModel> items, SushiItemRes page) {
  if (page.backdrop.isEmpty && page.logo.isEmpty) return items;
  var changed = false;
  final out = <ItemBaseModel>[];
  for (final item in items) {
    if (!sushiHomeItemMatchesPage(item, page)) {
      out.add(item);
      continue;
    }
    changed = true;
    out.add(sushiAttachTitleImages(item, page));
  }
  return changed ? out : items;
}

typedef SushiTitlePageLookup = Future<SushiItemRes?> Function({required int tmdbId, required SushiKind kind});

/// Overlay cached `/item` images onto compact home cards. Misses stay poster-only.
Future<List<ItemBaseModel>> sushiAttachCachedTitleImages(
  List<ItemBaseModel> items,
  SushiTitlePageLookup peek,
) {
  return Future.wait(items.map((item) async {
    final identity = sushiContinueIdentity(item);
    if (identity == null) return item;
    if (item.images?.backDrop?.isNotEmpty == true || item.getPosters?.backDrop?.isNotEmpty == true) {
      return item;
    }
    final page = await peek(tmdbId: identity.tmdbId, kind: identity.kind);
    if (page == null || (page.backdrop.isEmpty && page.logo.isEmpty)) return item;
    return sushiAttachTitleImages(item, page);
  }));
}

/// Merges a fetched [SushiItemRes] (overview) and its files (mediaStreams) into an already-shown
/// [MovieModel] — called after the home-rail placeholder is on screen, same "paint first, enrich
/// after" shape `movies_details_provider.dart` already uses for Sushi.
MovieModel sushiEnrichMovieModel(
  MovieModel base,
  SushiItemRes item,
  List<SushiFile> files, {
  int? preferredFileId,
  SushiMediaVariantPreference? localPreference,
}) {
  final genreNames = item.genres
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final people = [
    for (var i = 0; i < item.people.length; i++)
      Person(
        id: item.people[i].tmdbId > 0
            ? 'sushi_person_${item.people[i].tmdbId}'
            : 'sushi_person_${item.row.tmdbId}_$i',
        name: item.people[i].name,
        role: item.people[i].role,
        image: sushiTmdbImage(
          item.people[i].profile,
          key: item.people[i].tmdbId > 0
              ? 'sushi_person_${item.people[i].tmdbId}'
              : 'sushi_person_${item.row.tmdbId}_$i',
          size: 'w185',
        ),
      ),
  ];
  final related = item.related.map(sushiRowToItemBaseModel).toList();
  sushiRememberCollection(base.id, item.collectionName, item.collection.map(sushiRowToItemBaseModel).toList());
  sushiRememberOriginCountry(base.id, item.country);

  return base.copyWith(
    images: sushiTitleImages(base.id, base.images, item),
    overview: base.overview.copyWith(
      summary: item.overview,
      yearAired: base.overview.yearAired ?? (item.releasedOn > 0 ? _yearFromUnixSeconds(item.releasedOn) : null),
      runTime: item.runtimeS > 0 ? Duration(seconds: item.runtimeS) : base.overview.runTime,
      genres: genreNames.isEmpty ? base.overview.genres : genreNames,
      genreItems: genreNames.isEmpty
          ? base.overview.genreItems
          : [
              for (final name in genreNames) GenreItems(id: name, name: name),
            ],
      people: people.isEmpty ? base.overview.people : people,
    ),
    mediaStreams: sushiBuildMediaStreams(files, preferredFileId: preferredFileId, localPreference: localPreference),
    related: related,
    canDownload: sushiPickReadyFile(files) != null,
  );
}

List<EpisodeModel> sushiEpisodesFromItem(SeriesModel series, SushiItemRes item) {
  return sushiEpisodesFromWire(series, item.episodes);
}

List<EpisodeModel> sushiEpisodesFromWire(SeriesModel series, List<SushiEpisode> episodes) {
  final sorted = episodes.where((e) => e.episodeId != 0).toList()
    ..sort((a, b) {
      final bySeason = a.seasonNo.compareTo(b.seasonNo);
      return bySeason != 0 ? bySeason : a.episodeNo.compareTo(b.episodeNo);
    });
  return [
    for (final e in sorted)
      EpisodeModel(
        seriesName: series.name,
        season: e.seasonNo,
        episode: e.episodeNo,
        episodeEnd: null,
        location: ItemLocation.filesystem,
        name: e.title.isEmpty ? 'Episode ${e.episodeNo}' : e.title,
        id: '$_sushiEpisodeIdPrefix${e.episodeId}',
        overview: OverviewModel(summary: e.title, runTime: series.overview.runTime),
        parentId: series.id,
        playlistId: null,
        images: series.images,
        childCount: null,
        primaryRatio: 1.78,
        userData: const UserData(),
        parentImages: series.images,
        mediaStreams: MediaStreamsModel(versionStreams: const []),
        canDelete: false,
        canDownload: true,
        jellyType: BaseItemKind.episode,
      ),
  ];
}

List<SeasonModel> sushiSeasonsFromIndex(
  SeriesModel series,
  List<SushiSeason> index,
  List<EpisodeModel> known,
) {
  final bySeason = known.episodesBySeason;
  return [
    for (final s in index)
      SeasonModel(
        parentImages: series.images,
        seasonName: s.seasonNo == 0 ? 'Specials' : 'Season ${s.seasonNo}',
        episodes: bySeason[s.seasonNo] ?? const [],
        episodeCount: s.episodeCount,
        seriesId: series.id,
        season: s.seasonNo,
        seriesName: series.name,
        name: s.seasonNo == 0 ? 'Specials' : 'Season ${s.seasonNo}',
        id: '$_sushiSeasonIdPrefix${series.id}_${s.seasonNo}',
        overview: series.overview,
        parentId: series.id,
        playlistId: null,
        images: series.images,
        childCount: s.episodeCount,
        primaryRatio: 0.7,
        userData: UserData(unPlayedItemCount: s.episodeCount),
        canDelete: false,
        canDownload: true,
        jellyType: BaseItemKind.season,
      ),
  ];
}

List<SeasonModel> sushiSeasonsFromEpisodes(SeriesModel series, List<EpisodeModel> episodes) {
  return [
    for (final entry in episodes.episodesBySeason.entries)
      SeasonModel(
        parentImages: series.images,
        seasonName: entry.key == 0 ? 'Specials' : 'Season ${entry.key}',
        episodes: entry.value,
        episodeCount: entry.value.length,
        seriesId: series.id,
        season: entry.key,
        seriesName: series.name,
        name: entry.key == 0 ? 'Specials' : 'Season ${entry.key}',
        id: '$_sushiSeasonIdPrefix${series.id}_${entry.key}',
        overview: series.overview,
        parentId: series.id,
        playlistId: null,
        images: series.images,
        childCount: entry.value.length,
        primaryRatio: 0.7,
        userData: UserData(unPlayedItemCount: entry.value.length),
        canDelete: false,
        canDownload: true,
        jellyType: BaseItemKind.season,
      ),
  ];
}

SeriesModel sushiEnrichSeriesModel(SeriesModel base, SushiItemRes item) {
  final genreNames = item.genres
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final people = [
    for (var i = 0; i < item.people.length; i++)
      Person(
        id: item.people[i].tmdbId > 0
            ? 'sushi_person_${item.people[i].tmdbId}'
            : 'sushi_person_${item.row.tmdbId}_$i',
        name: item.people[i].name,
        role: item.people[i].role,
        image: sushiTmdbImage(
          item.people[i].profile,
          key: item.people[i].tmdbId > 0
              ? 'sushi_person_${item.people[i].tmdbId}'
              : 'sushi_person_${item.row.tmdbId}_$i',
          size: 'w185',
        ),
      ),
  ];
  final related = item.related.map(sushiRowToItemBaseModel).toList();
  sushiRememberCollection(base.id, item.collectionName, item.collection.map(sushiRowToItemBaseModel).toList());
  sushiRememberOriginCountry(base.id, item.country);
  final images = sushiTitleImages(base.id, base.images, item);
  final overview = base.overview.copyWith(
    summary: item.overview,
    yearAired: base.overview.yearAired ?? (item.releasedOn > 0 ? _yearFromUnixSeconds(item.releasedOn) : null),
    runTime: item.runtimeS > 0 ? Duration(seconds: item.runtimeS) : base.overview.runTime,
    genres: genreNames.isEmpty ? base.overview.genres : genreNames,
    genreItems: genreNames.isEmpty
        ? base.overview.genreItems
        : [
            for (final name in genreNames) GenreItems(id: name, name: name),
          ],
    people: people.isEmpty ? base.overview.people : people,
  );
  final withMeta = base.copyWith(images: images, overview: overview);
  final episodes = sushiEpisodesFromItem(withMeta, item);
  final seasons = item.seasons.isNotEmpty
      ? sushiSeasonsFromIndex(withMeta, item.seasons, episodes)
      : sushiSeasonsFromEpisodes(withMeta, episodes);
  final episodeCount = item.seasons.isNotEmpty
      ? item.seasons.fold<int>(0, (n, s) => n + s.episodeCount)
      : episodes.length;

  return withMeta.copyWith(
    related: related,
    availableEpisodes: episodes,
    seasons: seasons,
    childCount: episodeCount,
    canDownload: false,
  );
}

/// Season fill replaces the lite play-target row with a fresh wire episode.
/// That row has no `/files` yet, so a ready version already attached must stay
/// or the header flips from Play to Request.
EpisodeModel _sushiKeepAttachedStreams(EpisodeModel? previous, EpisodeModel loaded) {
  if (previous == null) return loaded;
  if (loaded.mediaStreams.versionStreams.isNotEmpty) return loaded;
  if (previous.mediaStreams.versionStreams.isEmpty) return loaded;
  return loaded.copyWith(
    mediaStreams: previous.mediaStreams,
    canDownload: previous.canDownload,
    overview: previous.overview,
  );
}

SeriesModel sushiMergeSeasonEpisodes(SeriesModel series, int seasonNo, List<EpisodeModel> loaded) {
  final previous = {
    for (final episode in series.availableEpisodes ?? const <EpisodeModel>[])
      if (episode.season == seasonNo) episode.id: episode,
  };
  final loadedKept = [
    for (final episode in loaded) _sushiKeepAttachedStreams(previous[episode.id], episode),
  ];
  final kept = [
    for (final episode in series.availableEpisodes ?? const <EpisodeModel>[])
      if (episode.season != seasonNo) episode,
  ];
  final merged = [...kept, ...loadedKept]
    ..sort((a, b) {
      final bySeason = a.season.compareTo(b.season);
      return bySeason != 0 ? bySeason : a.episode.compareTo(b.episode);
    });
  return series.copyWith(
    availableEpisodes: merged,
    seasons: [
      for (final season in series.seasons ?? const <SeasonModel>[])
        season.season == seasonNo ? season.copyWith(episodes: loadedKept) : season,
    ],
  );
}

/// Episode id whose `/files` pick-list should land on [series].
///
/// Header Play follows [SeriesModel.nextUp] (resume), not row focus — except when the user
/// already picked [SeriesModel.selectedEpisode].
int? sushiSeriesPlayFilesEpisodeId(SeriesModel series) {
  final playTarget = series.selectedEpisode ?? series.nextUp;
  if (playTarget == null) return null;
  return sushiEpisodeIdFromItemId(playTarget.id);
}

/// Attaches the `/files` pick-list to the episode those files belong to.
///
/// `/item` only wires one play-target episode (ADR 0028, usually S01E01). Continue-watching
/// then injects a resume stub so `nextUp` can be S01E13. Passing [filesEpisodeId] keeps E1's
/// files on E1 instead of gluing them onto the E13 stub (Play would show S1 E13 and start E1).
/// Pending-only / empty lists leave [ItemBaseModel.canDownload] false so Play/Sync stay hidden.
SeriesModel sushiApplySeriesFiles(
  SeriesModel next,
  List<SushiFile> files, {
  int? preferredFileId,
  SushiMediaVariantPreference? localPreference,
  int? filesEpisodeId,
}) {
  final playTarget = next.selectedEpisode ?? next.nextUp;
  if (playTarget == null) return next.copyWith(canDownload: false);
  var targetId = playTarget.id;
  if (filesEpisodeId != null) {
    final match = (next.availableEpisodes ?? const <EpisodeModel>[]).firstWhereOrNull(
      (episode) => sushiEpisodeIdFromItemId(episode.id) == filesEpisodeId,
    );
    if (match == null) return next.copyWith(canDownload: false);
    targetId = match.id;
  }
  final streams = sushiBuildMediaStreams(files, preferredFileId: preferredFileId, localPreference: localPreference);
  final ready = streams.versionStreams.isNotEmpty;
  return next.copyWith(
    canDownload: ready,
    availableEpisodes: [
      for (final episode in next.availableEpisodes ?? const <EpisodeModel>[])
        episode.id == targetId
            ? episode.copyWith(
                mediaStreams: streams,
                overview: sushiOverviewWithFileRunTime(
                  episode.overview,
                  files,
                  lastFileId: preferredFileId ?? 0,
                ),
              )
            : episode,
    ],
  );
}

final Map<String, ({String name, List<ItemBaseModel> items})> _sushiCollections = {};

void sushiRememberCollection(String itemId, String name, List<ItemBaseModel> items) {
  if (items.isEmpty) {
    _sushiCollections.remove(itemId);
    return;
  }
  _sushiCollections[itemId] = (name: name, items: items);
}

({String name, List<ItemBaseModel> items})? sushiCollectionFor(String itemId) =>
    _sushiCollections[itemId];

final Map<String, String> _sushiOriginCountries = {};

void sushiRememberOriginCountry(String itemId, String iso) {
  final code = iso.trim().toUpperCase();
  if (code.length != 2) {
    _sushiOriginCountries.remove(itemId);
    return;
  }
  _sushiOriginCountries[itemId] = code;
}

String? sushiOriginCountry(String itemId) => _sushiOriginCountries[itemId];

/// Cast tap uses TMDB person id when present (`sushi_person_{tmdbId}`).
PersonModel sushiPersonModel(Person person, {SushiPersonRes? page}) {
  final movies = page?.movies.map(sushiRowToItemBaseModel).toList() ?? const <ItemBaseModel>[];
  final series = page?.series.map(sushiRowToItemBaseModel).toList() ?? const <ItemBaseModel>[];
  return PersonModel(
    name: page?.name.isNotEmpty == true ? page!.name : person.name,
    id: person.id,
    birthPlace: const [],
    movies: movies.whereType<MovieModel>().toList(),
    series: series.whereType<SeriesModel>().toList(),
    overview: OverviewModel(
      summary: page?.biography.isNotEmpty == true ? page!.biography : person.role,
    ),
    parentId: null,
    playlistId: null,
    images: ImagesData(
      primary: page != null && page.profile.isNotEmpty
          ? sushiTmdbImage(page.profile, key: person.id, size: 'w185')
          : person.image,
    ),
    childCount: movies.length + series.length,
    primaryRatio: 0.667,
    userData: const UserData(),
  );
}

int? sushiPersonTmdbIdFromId(String id) {
  const prefix = 'sushi_person_';
  if (!id.startsWith(prefix)) return null;
  final rest = id.substring(prefix.length);
  if (rest.contains('_')) return null; // legacy index-based id
  return int.tryParse(rest);
}

int _yearFromUnixSeconds(int unixSeconds) =>
    DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true).year;
