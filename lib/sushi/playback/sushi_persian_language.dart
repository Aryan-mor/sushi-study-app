import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';

/// Persian / Iranian language detection for OX subtitle UI.
abstract final class SushiPersianLanguage {
  static const _languageCodes = {
    'fa',
    'fas',
    'per',
    'pes',
    'fae',
  };

  static bool isPersianLanguage(String? language) {
    if (language == null || language.isEmpty || language == 'Unknown') return false;
    final normalized = language.trim().toLowerCase().replaceAll('_', '-');
    final primary = normalized.split('-').first;
    if (_languageCodes.contains(primary)) return true;
    return normalized.contains('persian') ||
        normalized.contains('farsi') ||
        language.contains('فارسی');
  }

  /// True when the played item's primary (or any) audio track is Persian.
  static bool isPersianFilm(PlaybackModel? playbackModel) {
    return isPersianFilmFromStreams(playbackModel?.mediaStreams);
  }

  static bool isPersianFilmFromStreams(MediaStreamsModel? streams) {
    if (streams == null) return false;

    final audios = streams.audioStreams.where((stream) => stream.index != -1).toList();
    if (audios.isEmpty) return false;

    final defaultIndex = streams.defaultAudioStreamIndex;
    final defaultAudio = audios.firstWhere(
      (stream) => stream.index == defaultIndex,
      orElse: () => audios.first,
    );
    if (isPersianLanguage(defaultAudio.language) || isPersianLanguage(defaultAudio.displayTitle)) {
      return true;
    }

    for (final stream in audios) {
      if (isPersianLanguage(stream.language) || isPersianLanguage(stream.displayTitle)) {
        return true;
      }
    }

    for (final stream in streams.subStreams) {
      if (isPersianLanguage(stream.language) || isPersianLanguage(stream.displayTitle)) {
        return true;
      }
    }

    for (final stream in streams.versionStreams) {
      if (isPersianLanguage(stream.name)) return true;
    }

    return false;
  }

  static bool showIranFlagForSubtitle({
    required String? subtitleLanguage,
    PlaybackModel? playbackModel,
    MediaStreamsModel? mediaStreams,
    required int subtitleIndex,
  }) {
    if (subtitleIndex == -1) return false;
    if (isPersianLanguage(subtitleLanguage)) return true;
    if (isPersianFilm(playbackModel)) return true;
    return isPersianFilmFromStreams(mediaStreams);
  }
}

/// Letter counts in a subtitle sample. Arabic-script block is what a Persian cue looks like
/// when the container language tag is wrong.
class SushiSubtitleScriptCounts {
  const SushiSubtitleScriptCounts({required this.arabic, required this.latin});

  final int arabic;
  final int latin;

  int get letters => arabic + latin;
}

SushiSubtitleScriptCounts sushiSubtitleScriptCounts(String sample) {
  var arabic = 0;
  var latin = 0;
  for (final r in sample.runes) {
    final arabicScript = (r >= 0x0600 && r <= 0x06FF) ||
        (r >= 0x0750 && r <= 0x077F) ||
        (r >= 0xFB50 && r <= 0xFDFF) ||
        (r >= 0xFE70 && r <= 0xFEFF);
    if (arabicScript) {
      arabic++;
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
      latin++;
    }
  }
  return SushiSubtitleScriptCounts(arabic: arabic, latin: latin);
}

/// True when [sample] is mostly Persian/Arabic letters, not a Latin subtitle with one credit line.
bool sushiSubtitleSampleLooksPersian(String sample) {
  final counts = sushiSubtitleScriptCounts(sample);
  if (counts.letters < 12) return false;
  return counts.arabic >= 8 && counts.arabic * 2 >= counts.latin;
}

/// True when [sample] has enough Latin text to rule Persian out.
/// Empty or a few letters is not a decision: the sniff often ends before the first cue.
bool sushiSubtitleSampleRejectsPersian(String sample) {
  final counts = sushiSubtitleScriptCounts(sample);
  if (counts.letters < 24) return false;
  return !sushiSubtitleSampleLooksPersian(sample);
}
