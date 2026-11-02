import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_playback_user_data_derive.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

/// Overlay client watch state onto a catalog movie.
///
/// `/item` has no UserData. Played lives in `/me/item-flags`. Resume lives in
/// the continue-watching store. The movie play button reads [MovieModel.userData],
/// so this must run after every enrich — same contract as [sushiPaintSeriesWatchState].
MovieModel sushiPaintMovieWatchState(
  MovieModel movie, {
  Set<String> playedIds = const {},
  SushiContinueEntry? resume,
  SushiFilesRes? files,
}) {
  if (playedIds.contains(movie.id)) {
    return movie.copyWith(
      userData: movie.userData.copyWith(
        played: true,
        progress: 0,
        playbackPositionTicks: 0,
      ),
    );
  }
  if (resume != null && !resume.isFinished && resume.kind == SushiKind.movie) {
    return movie.copyWith(
      userData: movie.userData.copyWith(
        played: false,
        progress: resume.progressPct,
        playbackPositionTicks: resume.positionMs * 10000,
        lastPlayed: DateTime.fromMillisecondsSinceEpoch(resume.atMs),
      ),
    );
  }
  final fromServer = sushiUserDataFromFiles(files);
  if (fromServer != null) {
    return movie.copyWith(userData: fromServer);
  }
  return movie;
}

/// Continue store lookup + paint. Call after catalog enrich.
Future<MovieModel> sushiLoadAndPaintMovieWatchState(
  MovieModel movie, {
  Set<String> playedIds = const {},
  SushiFilesRes? files,
}) async {
  final tmdbId = sushiTmdbIdFromItemId(movie.id);
  final resume = tmdbId == null
      ? null
      : await sushiContinueFind(tmdbId: tmdbId, kind: SushiKind.movie);
  return sushiPaintMovieWatchState(movie, playedIds: playedIds, resume: resume, files: files);
}
