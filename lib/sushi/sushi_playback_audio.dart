import 'package:collection/collection.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';

/// Resolves a playable audio stream when Jellyfin default index is wrong (e.g. 0 = video).
AudioStreamModel? sushiResolvePlaybackAudioStream(PlaybackModel model) {
  final streams = model.audioStreams;
  if (streams == null || streams.isEmpty) return null;

  final wantIdx = model.mediaStreams?.defaultAudioStreamIndex;
  final matched = streams.firstWhereOrNull((s) => s.index == wantIdx);
  if (matched != null && matched.index != AudioStreamModel.no().index) {
    return matched;
  }

  return streams.firstWhereOrNull((s) => s.index >= 0);
}

/// Sushi files with empty `audio_langs` still mux audio. Forcing the picker
/// "Off" sentinel (`index == -1`) onto libMPV/libMDK mutes playback.
bool sushiShouldSkipAudioTrackOff(PlaybackModel playbackModel) {
  return !playbackModel.isAudioPlayback;
}

/// Native Exo treats a negative default as "disable audio". Never send Off
/// on first load — fall back to the first real catalog index, then 1.
int sushiDefaultAudioTrackIndex(PlaybackModel model) {
  final resolved = sushiResolvePlaybackAudioStream(model)?.index;
  if (resolved != null && resolved >= 0) return resolved;
  final fallback = model.mediaStreams?.defaultAudioStreamIndex;
  if (fallback != null && fallback >= 0) return fallback;
  return 1;
}
