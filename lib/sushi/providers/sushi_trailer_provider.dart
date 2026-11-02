import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

/// Trailer key + watched flag for one title's Play row (docs/12 §4, ADR 0031). Reads straight from
/// the cached title page and the local watched-state mirror (docs/11 §6.1) -- no new field on the
/// (inherited Fladder) item models, since neither of those lives there.
class SushiTrailerState {
  const SushiTrailerState({required this.trailerKey, required this.watched});

  final String trailerKey;
  final bool watched;

  static const none = SushiTrailerState(trailerKey: '', watched: false);

  bool get hasTrailer => trailerKey.isNotEmpty;

  /// Never started: its own button beside Play (or beside Request, or alone).
  bool get showBesidePlay => hasTrailer && !watched;

  /// Watched, or already started (Resume): last overflow entry above Movie info.
  bool get showInMenu => hasTrailer && watched;
}

final sushiTrailerStateProvider =
    FutureProvider.family<SushiTrailerState, ({String itemId, SushiKind kind})>((ref, args) async {
  final tmdbId = sushiTmdbIdFromItemId(args.itemId);
  if (tmdbId == null) return SushiTrailerState.none;
  final catalog = ref.watch(sushiCatalogControllerProvider);
  final page = await catalog.peekCachedTitle(tmdbId: tmdbId, kind: args.kind);
  final trailerKey = page?.trailerKey ?? '';
  if (trailerKey.isEmpty) return SushiTrailerState.none;
  final episodeId = page?.episodes.firstOrNull?.episodeId;
  final done =
      episodeId != null && episodeId != 0 ? await catalog.isEpisodeWatched(episodeId) : false;
  final resume = await sushiContinueFind(tmdbId: tmdbId, kind: args.kind);
  final started = resume != null && resume.positionMs > 0;
  return SushiTrailerState(trailerKey: trailerKey, watched: done || started);
});
