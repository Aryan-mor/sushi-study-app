import 'package:fladder/jellyfin/enum_models.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_playback_user_data_derive.dart';
import 'package:fladder/sushi/sushi_season_user_data.dart';

/// Overlay client watch state onto catalog episodes.
///
/// `/item` has no UserData. Played lives in `/me/item-flags`. Resume lives in
/// the continue-watching store. `nextUp` and the series play button both read
/// [EpisodeModel.userData], so this must run after every enrich.
SeriesModel sushiPaintSeriesWatchState(
  SeriesModel series, {
  Set<String> playedIds = const {},
  SushiContinueEntry? resume,
  SushiFilesRes? files,
  int? filesEpisodeId,
}) {
  var withResume = sushiAttachResumeEpisode(series, resume);
  final episodes = withResume.availableEpisodes;
  if (episodes == null || episodes.isEmpty) return withResume;

  final painted = [
    for (final episode in episodes)
      episode.copyWith(
        userData: _watchUserData(
          episode,
          playedIds: playedIds,
          resume: resume,
          files: files,
          filesEpisodeId: filesEpisodeId,
        ),
      ),
  ];

  return withResume.copyWith(
    availableEpisodes: painted,
    seasons: [
      for (final season in withResume.seasons ?? const <SeasonModel>[])
        season.copyWith(
          episodes: painted.where((e) => e.season == season.season).toList(),
          userData: sushiSeasonUserDataFromEpisodes(
            painted.where((e) => e.season == season.season),
          ),
        ),
    ],
  );
}

UserData _watchUserData(
  EpisodeModel episode, {
  required Set<String> playedIds,
  SushiContinueEntry? resume,
  SushiFilesRes? files,
  int? filesEpisodeId,
}) {
  if (playedIds.contains(episode.id)) {
    return episode.userData.copyWith(
      played: true,
      progress: 0,
      playbackPositionTicks: 0,
    );
  }
  if (resume != null && !resume.isFinished && _resumeMatches(episode, resume)) {
    return episode.userData.copyWith(
      played: false,
      progress: resume.progressPct,
      playbackPositionTicks: resume.positionMs * 10000,
    );
  }
  final epId = sushiEpisodeIdFromItemId(episode.id);
  if (files != null && filesEpisodeId != null && epId == filesEpisodeId) {
    final fromServer = sushiUserDataFromFiles(files);
    if (fromServer != null) return fromServer;
  }
  return episode.userData;
}

SeriesModel sushiAttachResumeEpisode(SeriesModel series, SushiContinueEntry? resume) {
  if (resume == null || resume.isFinished) return series;
  final id = resume.episodeItemId;
  final season = resume.season;
  final episode = resume.episode;
  final hasId = id != null && id.isNotEmpty;
  if (!hasId && (season == null || episode == null)) return series;
  final alreadyKnown = hasId
      ? series.availableEpisodes?.any((e) => e.id == id) == true
      : series.availableEpisodes?.any((e) => e.season == season && e.episode == episode) == true;
  if (alreadyKnown) return series;
  final stub = sushiEpisodeStub(
    series,
    season: season ?? 1,
    episode: episode ?? 1,
    id: id,
  );
  return series.copyWith(
    availableEpisodes: [...?series.availableEpisodes, stub],
  );
}

String sushiEpisodeStubId(String seriesId, int season, int episode) =>
    'sushi_ep_stub_${seriesId}_${season}_$episode';

bool sushiEpisodeIsCatalogStub(EpisodeModel episode) => episode.id.startsWith('sushi_ep_stub_');

/// Placeholder episode for a season/episode number the client has no catalog row for yet
/// (resume reattach, or a season index that still claims episodes the client has not loaded).
EpisodeModel sushiEpisodeStub(
  SeriesModel series, {
  required int season,
  required int episode,
  String? id,
}) {
  return EpisodeModel(
    seriesName: series.name,
    season: season,
    episode: episode,
    episodeEnd: null,
    location: ItemLocation.filesystem,
    name: 'Episode $episode',
    id: id ?? sushiEpisodeStubId(series.id, season, episode),
    overview: series.overview,
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
  );
}

/// Overlay local continue-watching resume onto a single episode so next/prev
/// skip can restart at the saved position instead of 0.
EpisodeModel sushiOverlayResumeOnEpisode(EpisodeModel episode, SushiContinueEntry? resume) {
  if (resume == null || resume.isFinished || !_resumeMatches(episode, resume)) {
    return episode;
  }
  return episode.copyWith(
    userData: episode.userData.copyWith(
      played: false,
      progress: resume.progressPct,
      playbackPositionTicks: resume.positionMs * 10000,
    ),
  );
}

bool _resumeMatches(EpisodeModel episode, SushiContinueEntry resume) {
  final episodeItemId = resume.episodeItemId;
  if (episodeItemId != null && episodeItemId.isNotEmpty) {
    return episode.id == episodeItemId;
  }
  final season = resume.season;
  final number = resume.episode;
  if (season != null && number != null) {
    return episode.season == season && episode.episode == number;
  }
  return false;
}
