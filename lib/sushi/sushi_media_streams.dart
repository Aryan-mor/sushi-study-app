import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';

export 'package:fladder/sushi/sushi_variant_label.dart' show sushiVersionStreamLabel;

/// Whether the detail page should show stream pickers (version / audio / sub).
///
/// Fladder gates on [MediaStreamsModel.isNotEmpty] (audio + subs required).
/// OX items may have multiple file variants before probe completes — still show
/// the version picker when more than one [MediaSource] exists.
bool sushiShowMediaStreamHelper(MediaStreamsModel streams) {
  return streams.versionStreams.isNotEmpty;
}

/// Whether the file/version picker should appear in the detail header.
///
/// OX always shows the current file label when at least one variant exists,
/// even when there is only one playable option.
bool sushiShowVersionStreamPicker(MediaStreamsModel streams) {
  return streams.versionStreams.isNotEmpty;
}

/// Browse-only or catalog movies without attached files have no version streams.
bool sushiMovieHasPlayableMedia(MovieModel movie) {
  return movie.mediaStreams.versionStreams.isNotEmpty;
}
