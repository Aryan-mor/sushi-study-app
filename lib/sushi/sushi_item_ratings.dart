/// SushiRatings from Jellyfin item JSON (Seerr ratings API removed).
class SushiItemRatings {
  final int? rtCritics;
  final int? rtAudience;
  final double? imdbScore;

  const SushiItemRatings({
    this.rtCritics,
    this.rtAudience,
    this.imdbScore,
  });

  bool get hasRt => rtCritics != null;
}

SushiItemRatings? sushiParseItemRatingsJson(dynamic raw) {
  if (raw is! Map) return null;

  int? asInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.round();
    return int.tryParse('$v');
  }

  double? asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  final rtRaw = raw['rt'] ?? raw['Rt'] ?? raw['rottenTomatoes'];
  int? rtCritics;
  int? rtAudience;
  if (rtRaw is Map) {
    rtCritics = asInt(rtRaw['criticsScore'] ?? rtRaw['CriticsScore']);
    rtAudience = asInt(rtRaw['audienceScore'] ?? rtRaw['AudienceScore']);
  }

  final imdbRaw = raw['imdb'] ?? raw['Imdb'];
  double? imdbScore;
  if (imdbRaw is Map) {
    imdbScore = asDouble(imdbRaw['criticsScore'] ?? imdbRaw['rating'] ?? imdbRaw['Rating']);
  } else {
    imdbScore = asDouble(imdbRaw);
  }

  if (rtCritics == null && rtAudience == null && imdbScore == null) return null;
  return SushiItemRatings(
    rtCritics: rtCritics,
    rtAudience: rtAudience,
    imdbScore: imdbScore,
  );
}
