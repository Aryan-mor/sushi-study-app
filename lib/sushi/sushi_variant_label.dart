import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/sushi/sushi_media_variant.dart';

const _knownSourceTokens = {
  'web-dl',
  'webdl',
  'webrip',
  'bluray',
  'blu-ray',
  'hdtv',
  'remux',
};

/// Localized file/version label: `1080p - English - BluRay`, `1080p - dubbed (Persian) - WEB-DL`.
String sushiLocalizedVersionStreamLabel(AppLocalizations l10n, VersionStreamModel stream) {
  final meta = sushiClassifyVersionStream(stream);
  final resolution = _resolutionLabel(meta, stream);
  final source = _sourceLabel(stream);
  final language = _localizedLanguageName(l10n, _primaryLanguage(stream));
  final middle = _middleLabel(l10n, meta.delivery, language);
  final parts = [resolution, middle, source].where((part) => part.isNotEmpty);
  return parts.join(' - ');
}

/// Picker label for [stream]. Pass the whole pick-list as [siblings]: when two versions would read
/// the same (six `720p`s, or six copies of one raw release filename), each gets its file size so
/// the list can still be told apart.
String sushiVersionStreamLabel(
  VersionStreamModel stream, {
  AppLocalizations? l10n,
  List<VersionStreamModel>? siblings,
}) {
  final custom = stream.displayName.trim();
  if (custom.isNotEmpty) {
    final size = stream.sizeBytes;
    if (siblings == null || size == null || size <= 0) return custom;
    final clashes = siblings.where((s) => !identical(s, stream) && s.displayName.trim() == custom);
    if (clashes.isEmpty) return custom;
    return '$custom · ${sushiFileSizeLabel(size)}';
  }
  final label = _baseVersionStreamLabel(stream, l10n: l10n);
  final size = stream.sizeBytes;
  if (siblings == null || size == null || size <= 0) return label;
  final clashes = siblings.where((s) => !identical(s, stream) && _baseVersionStreamLabel(s, l10n: l10n) == label);
  if (clashes.isEmpty) return label;
  return '$label · ${sushiFileSizeLabel(size)}';
}

/// `800 MB`, `1.4 GB` -- short enough for a TV picker row.
String sushiFileSizeLabel(int bytes) {
  const mb = 1024 * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  return '${(bytes / mb).round()} MB';
}

String _baseVersionStreamLabel(
  VersionStreamModel stream, {
  AppLocalizations? l10n,
}) {
  final serverName = stream.name.trim();
  if (serverName.isNotEmpty) {
    if (_looksLikeRawFilename(serverName)) {
      final composed = _labelFromRawFilename(stream, serverName, l10n: l10n);
      if (composed.isNotEmpty) {
        return composed;
      }
    }
    if (l10n != null) {
      return _localizeServerVariantLabel(l10n, serverName);
    }
    return serverName;
  }
  if (l10n != null) {
    final localized = sushiLocalizedVersionStreamLabel(l10n, stream);
    if (localized.isNotEmpty) {
      return localized;
    }
  }
  if (serverName.isNotEmpty) {
    return serverName;
  }
  final resolution = stream.detailedResolutionLabel.trim();
  if (resolution.isNotEmpty && resolution != 'Unknown Unknown') {
    return resolution;
  }
  final id = stream.id?.trim();
  if (id != null && id.isNotEmpty) {
    return id.replaceFirst(RegExp(r'^ms_'), 'Variant ');
  }
  return 'Variant ${stream.index + 1}';
}

/// Localize delivery/language tokens in a server-built label; keep technical segments intact.
String _localizeServerVariantLabel(AppLocalizations l10n, String serverName) {
  final parts = serverName.split(' - ').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) {
    return serverName;
  }
  final localized = parts.map((part) => _localizeServerVariantSegment(l10n, part)).toList();
  return localized.join(' - ');
}

String _localizeServerVariantSegment(AppLocalizations l10n, String segment) {
  final lower = segment.toLowerCase();
  if (lower == 'soft sub' || lower == 'softsub') {
    return l10n.sushiVariantSoftSub;
  }
  if (lower == 'hard sub' || lower == 'hardsub') {
    return l10n.sushiVariantHardSubGeneric;
  }
  if (lower == 'dubbed') {
    return l10n.sushiVariantDubbedGeneric;
  }
  final dubbed = RegExp(r'^dubbed\s*\(([^)]+)\)$', caseSensitive: false).firstMatch(segment);
  if (dubbed != null) {
    final lang = _localizedLanguageName(l10n, dubbed.group(1));
    return l10n.sushiVariantDubbed(lang);
  }
  final hardSub = RegExp(r'^hard sub\s*\(([^)]+)\)$', caseSensitive: false).firstMatch(segment);
  if (hardSub != null) {
    final lang = _localizedLanguageName(l10n, hardSub.group(1));
    return l10n.sushiVariantHardSub(lang);
  }
  if (_looksLikeLanguageSegment(segment)) {
    return _localizedLanguageName(l10n, segment);
  }
  // A compact server label (`720p x265 Dub`, catalog.EnrichLabel) carries the delivery as a token.
  return segment.replaceAllMapped(_deliveryTokenRegex, (m) {
    return switch (m.group(1)!.toLowerCase()) {
      'softsub' => l10n.sushiVariantSoftSub,
      'hardsub' => l10n.sushiVariantHardSubGeneric,
      _ => l10n.sushiVariantDubbedGeneric,
    };
  });
}

final _deliveryTokenRegex = RegExp(r'(?<![A-Za-z])(SoftSub|HardSub|Dub)(?![A-Za-z])');

bool _looksLikeLanguageSegment(String segment) {
  switch (segment.toLowerCase()) {
    case 'english':
    case 'persian':
    case 'farsi':
    case 'arabic':
    case 'german':
    case 'french':
    case 'spanish':
    case 'russian':
    case 'japanese':
    case 'korean':
    case 'chinese':
    case 'turkish':
    case 'original':
    case 'dual':
      return true;
    default:
      return RegExp(r'^[a-z]{2,3}$', caseSensitive: false).hasMatch(segment);
  }
}

String _resolutionLabel(SushiVersionStreamMeta meta, VersionStreamModel stream) {
  final height = meta.qualityHeight;
  if (height != null) {
    if (height >= 2160) return '2160p';
    if (height >= 1440) return '1440p';
    if (height >= 1080) return '1080p';
    if (height >= 720) return '720p';
    if (height >= 576) return '576p';
    if (height >= 480) return '480p';
    if (height >= 360) return '360p';
    return '${height}p';
  }
  final fromName = _segments(stream.name).firstOrNull;
  if (fromName != null && _looksLikeResolution(fromName)) {
    return fromName;
  }
  final detailed = stream.detailedResolutionLabel.trim();
  final firstToken = detailed.split(' ').firstOrNull;
  if (firstToken != null && _looksLikeResolution(firstToken)) {
    return firstToken;
  }
  return '';
}

String _sourceLabel(VersionStreamModel stream) {
  final segments = _segments(stream.name);
  if (segments.length >= 3) {
    return _normalizeSource(segments.last);
  }
  for (final segment in segments) {
    if (_looksLikeSource(segment)) {
      return _normalizeSource(segment);
    }
  }
  return '';
}

List<String> _segments(String name) {
  return name.split(' - ').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
}

bool _looksLikeResolution(String value) {
  final lower = value.toLowerCase();
  return lower == '4k' || RegExp(r'^\d+p$').hasMatch(lower);
}

bool _looksLikeSource(String value) {
  final lower = value.toLowerCase();
  if (_knownSourceTokens.contains(lower)) return true;
  return _normalizeSource(value) != value;
}

String _normalizeSource(String value) {
  final lower = value.toLowerCase();
  switch (lower) {
    case 'web-dl':
    case 'webdl':
      return 'WEB-DL';
    case 'webrip':
      return 'WEBRip';
    case 'bluray':
    case 'blu-ray':
      return 'BluRay';
    case 'hdtv':
      return 'HDTV';
    case 'remux':
      return 'REMUX';
    default:
      return value;
  }
}

// Separator-aware "boundary" — `\b` doesn't break between `_`/`.` and a digit/letter,
// so an underscore/dot-delimited release filename (`..._1080p_...`) never matches `\b`-anchored
// regexes. These match/require a non-alphanumeric char (or string edge) around the token instead.
const _rawTokenBefore = r'(?:^|[^a-z0-9])';
const _rawTokenAfter = r'(?:$|[^a-z0-9])';

final _rawResolutionRegex = RegExp(
  '$_rawTokenBefore(2160|1440|1080|720|576|480|360)p$_rawTokenAfter',
  caseSensitive: false,
);
final _rawCodecRegex = RegExp(
  '$_rawTokenBefore(x264|x265|h\\.?264|h\\.?265|hevc|avc)$_rawTokenAfter',
  caseSensitive: false,
);
final _rawBitDepthRegex = RegExp(
  '$_rawTokenBefore(8|10|12)[\\s_.-]?bit$_rawTokenAfter',
  caseSensitive: false,
);

/// A server `qualityLabel` is normally pre-formatted as `' - '`-joined segments
/// (`"1080p - soft sub - WEB-DL"`). When the server instead sends a raw release
/// filename (underscore/dot separated, e.g. `One_Night_Only_2026_1080p_..._DigiMovi.mkv`),
/// that whole string is one unsplit segment and passes through the segment localizer
/// untouched — this detects that case so it can be routed through token parsing instead.
bool _looksLikeRawFilename(String name) {
  if (name.contains(' - ')) return false;
  final lower = name.toLowerCase();
  final looksLikeFile = lower.endsWith('.mkv') || lower.endsWith('.mp4') || lower.endsWith('.avi');
  final separatorCount = RegExp(r'[_.]').allMatches(name).length;
  if (separatorCount < 3 && !looksLikeFile) return false;
  return looksLikeFile ||
      _rawResolutionRegex.hasMatch(name) ||
      _rawCodecRegex.hasMatch(name);
}

String _canonicalCodecToken(String match) {
  final lower = match.toLowerCase().replaceAll('.', '');
  if (lower == 'hevc' || lower == 'h265' || lower == 'x265') return 'x265';
  if (lower == 'avc' || lower == 'h264' || lower == 'x264') return 'x264';
  return match;
}

String _deliveryShortToken(AppLocalizations? l10n, SushiStreamDelivery delivery) {
  switch (delivery) {
    case SushiStreamDelivery.softSub:
      return l10n?.sushiVariantSoftSub ?? 'SoftSub';
    case SushiStreamDelivery.hardSub:
      return l10n?.sushiVariantHardSubGeneric ?? 'HardSub';
    case SushiStreamDelivery.dubbed:
      return l10n?.sushiVariantDubbedGeneric ?? 'Dubbed';
    case SushiStreamDelivery.original:
    case SushiStreamDelivery.unknown:
      return '';
  }
}

/// Synthesizes a clean label (e.g. `1080p x265 10bit SoftSub`) from a raw release
/// filename by extracting the common tokens client-side, since the server sent the
/// filename verbatim instead of a pre-formatted label.
String _labelFromRawFilename(VersionStreamModel stream, String rawName, {AppLocalizations? l10n}) {
  final meta = sushiClassifyVersionStream(stream);
  final tokens = <String>[];

  final resMatch = _rawResolutionRegex.firstMatch(rawName);
  if (resMatch != null) {
    tokens.add('${resMatch.group(1)}p');
  } else if (meta.qualityHeight != null) {
    tokens.add('${meta.qualityHeight}p');
  }

  final codecMatch = _rawCodecRegex.firstMatch(rawName);
  if (codecMatch != null) {
    tokens.add(_canonicalCodecToken(codecMatch.group(1)!));
  }

  final bitDepthMatch = _rawBitDepthRegex.firstMatch(rawName);
  if (bitDepthMatch != null) {
    tokens.add('${bitDepthMatch.group(1)}bit');
  }

  final deliveryToken = _deliveryShortToken(l10n, meta.delivery);
  if (deliveryToken.isNotEmpty) {
    tokens.add(deliveryToken);
  }

  return tokens.join(' ');
}

String? _primaryLanguage(VersionStreamModel stream) {
  if (stream.audioStreams.isNotEmpty) {
    final audio = stream.audioStreams.firstWhere(
      (track) => track.language.trim().isNotEmpty,
      orElse: () => stream.audioStreams.first,
    );
    final fromAudio = audio.language.trim().isNotEmpty ? audio.language : audio.displayTitle;
    if (fromAudio.trim().isNotEmpty) {
      return fromAudio.trim();
    }
  }
  final blob = stream.name.toLowerCase();
  final dubbed = RegExp(r'dubbed\s*\(([^)]+)\)').firstMatch(blob);
  if (dubbed != null) {
    return dubbed.group(1)?.trim();
  }
  final hardSub = RegExp(r'hard sub\s*\(([^)]+)\)').firstMatch(blob);
  if (hardSub != null) {
    return hardSub.group(1)?.trim();
  }
  final segments = _segments(stream.name);
  if (segments.length == 3) {
    final middle = segments[1].toLowerCase();
    if (!middle.contains('dub') && !middle.contains('sub')) {
      return segments[1];
    }
  }
  if (segments.length == 2) {
    final middle = segments[1].toLowerCase();
    if (!middle.contains('dub') && !middle.contains('sub')) {
      return segments[1];
    }
  }
  return null;
}

String _middleLabel(AppLocalizations l10n, SushiStreamDelivery delivery, String? language) {
  final lang = language?.trim();
  switch (delivery) {
    case SushiStreamDelivery.dubbed:
      if (lang != null && lang.isNotEmpty) {
        return l10n.sushiVariantDubbed(lang);
      }
      return l10n.sushiVariantDubbedGeneric;
    case SushiStreamDelivery.softSub:
      return l10n.sushiVariantSoftSub;
    case SushiStreamDelivery.hardSub:
      if (lang != null && lang.isNotEmpty) {
        return l10n.sushiVariantHardSub(lang);
      }
      return l10n.sushiVariantHardSubGeneric;
    case SushiStreamDelivery.original:
    case SushiStreamDelivery.unknown:
      return lang ?? '';
  }
}

String _localizedLanguageName(AppLocalizations l10n, String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) {
    return '';
  }
  switch (value.toLowerCase()) {
    case 'en':
    case 'eng':
    case 'english':
      return l10n.sushiVariantLangEnglish;
    case 'fa':
    case 'fas':
    case 'per':
    case 'persian':
    case 'farsi':
      return l10n.sushiVariantLangPersian;
    case 'ar':
    case 'ara':
    case 'arabic':
      return l10n.sushiVariantLangArabic;
    case 'tr':
    case 'tur':
    case 'turkish':
      return l10n.sushiVariantLangTurkish;
    case 'de':
    case 'deu':
    case 'ger':
    case 'german':
      return l10n.sushiVariantLangGerman;
    case 'fr':
    case 'fra':
    case 'fre':
    case 'french':
      return l10n.sushiVariantLangFrench;
    case 'es':
    case 'spa':
    case 'spanish':
      return l10n.sushiVariantLangSpanish;
    case 'ru':
    case 'rus':
    case 'russian':
      return l10n.sushiVariantLangRussian;
    case 'ja':
    case 'jpn':
    case 'japanese':
      return l10n.sushiVariantLangJapanese;
    case 'ko':
    case 'kor':
    case 'korean':
      return l10n.sushiVariantLangKorean;
    case 'zh':
    case 'zho':
    case 'chi':
    case 'cmn':
    case 'chinese':
      return l10n.sushiVariantLangChinese;
    default:
      if (value.length <= 3) {
        return value.toUpperCase();
      }
      return value;
  }
}
