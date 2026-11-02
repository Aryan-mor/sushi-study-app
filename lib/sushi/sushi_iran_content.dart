import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/sushi/playback/sushi_persian_language.dart';
import 'package:fladder/sushi/playback/sushi_subtitle_font.dart';

/// OX-only Iranian content detection for detail metadata (same row as adult 🔞).
abstract final class SushiIranContent {
  static bool isIranian({
    List<String> tags = const [],
    List<GenreItems> genres = const [],
    String? name,
    String? originalTitle,
    MediaStreamsModel? mediaStreams,
  }) {
    

    for (final tag in tags) {
      final normalized = tag.trim().toLowerCase();
      if (normalized == 'ox:iran' || normalized.contains('iranian')) return true;
    }

    for (final genre in genres) {
      if (_isIranianGenre(genre.name)) return true;
    }

    if (name != null && SushiSubtitleFont.textUsesArabicScript(name)) return true;
    if (originalTitle != null && SushiSubtitleFont.textUsesArabicScript(originalTitle)) return true;

    return SushiPersianLanguage.isPersianFilmFromStreams(mediaStreams);
  }

  static bool _isIranianGenre(String? genre) {
    if (genre == null || genre.isEmpty) return false;
    final normalized = genre.trim().toLowerCase();
    return normalized.contains('iran') ||
        normalized.contains('persian') ||
        normalized.contains('فارسی') ||
        normalized.contains('ایران');
  }
}
