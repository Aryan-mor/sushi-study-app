import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's taste/onboarding audio answer (`user_prefs.audio`).
enum SushiAudioPref {
  /// Never asked, or an older server that does not send it.
  unset,

  /// Original audio with subtitles over a dub.
  original,

  /// A Persian dub over subtitles.
  dub,
}

/// Taste-wizard answer: play with subtitles, or leave them off.
enum SushiSubsPref {
  /// Never asked.
  unset,

  /// Subtitles on. Persian: hard sub, then Persian soft, then auto online.
  /// Any other language: auto online.
  on,

  /// Subtitles off. No auto online, and burned-in files are not the default.
  off,
}

/// Account-wide playback answers, delivered on `SyncRes` (docs/12 §5.2). They seed the version
/// pick for a title the user never chose a version for; an explicit per-title pick
/// (sushi_variant_preference_store.dart) and the server's last-played file both still win.
class SushiAccountPlaybackPref {
  const SushiAccountPlaybackPref({
    this.audio = SushiAudioPref.unset,
    this.maxHeight = 0,
    this.subtitleLang = '',
    this.subs = SushiSubsPref.unset,
  });

  factory SushiAccountPlaybackPref.fromWire(
    String audio,
    int maxHeight, [
    String subtitleLang = '',
    String subs = '',
  ]) {
    return SushiAccountPlaybackPref(
      audio: switch (audio.trim().toLowerCase()) {
        'original' => SushiAudioPref.original,
        'dub' => SushiAudioPref.dub,
        _ => SushiAudioPref.unset,
      },
      maxHeight: maxHeight > 0 ? maxHeight : 0,
      subtitleLang: subtitleLang.trim().toLowerCase(),
      subs: switch (subs.trim().toLowerCase()) {
        'on' => SushiSubsPref.on,
        'off' => SushiSubsPref.off,
        _ => SushiSubsPref.unset,
      },
    );
  }

  static const unset = SushiAccountPlaybackPref();

  final SushiAudioPref audio;

  /// 2160 / 1080 / 720 / 480; 0 when never asked.
  final int maxHeight;

  /// Preferred soft-sub language (ISO 639-1, e.g. `fa` / `en`); empty when never asked.
  final String subtitleLang;

  /// With / without subtitles. Stored on user_prefs and returned on Sync.
  /// An older server omits it; the device keeps the last answer until one arrives.
  final SushiSubsPref subs;

  bool get isUnset =>
      audio == SushiAudioPref.unset && maxHeight == 0 && subtitleLang.isEmpty && subs == SushiSubsPref.unset;

  bool get wantsSubtitlesOn => subs == SushiSubsPref.on;

  bool get wantsSubtitlesOff => subs == SushiSubsPref.off;

  /// Explicit "with subtitles" and a non-Persian language: every title starts on auto online.
  bool get wantsAutoOnlineSubtitles => wantsSubtitlesOn && !wantsPersianSubtitles;

  /// Empty or Persian — hardsub/dubbed files stay visible; AI uses the Persian prompt.
  bool get wantsPersianSubtitles => sushiSubtitleLangIsPersian(subtitleLang);

  /// Effective audio for version pick: non-Persian subtitle users never get a dub default.
  SushiAudioPref get audioForVersionPick =>
      wantsPersianSubtitles ? audio : (audio == SushiAudioPref.dub ? SushiAudioPref.original : audio);

  /// ISO code used for soft-sub matching / online search (`fa` when unset).
  String get subtitleLangOrFa =>
      subtitleLang.isEmpty ? 'fa' : subtitleLang;

  /// SubDL `languages` query value (FA, EN, ES, …).
  String get subdlLangCode => sushiSubtitleLangToSubdl(subtitleLangOrFa);

  /// English display name for UI / Gemini target ("Persian", "Spanish", …).
  String get subtitleLangDisplayEn => sushiSubtitleLangDisplayEn(subtitleLangOrFa);

  @override
  bool operator ==(Object other) =>
      other is SushiAccountPlaybackPref &&
      other.audio == audio &&
      other.maxHeight == maxHeight &&
      other.subtitleLang == subtitleLang &&
      other.subs == subs;

  @override
  int get hashCode => Object.hash(audio, maxHeight, subtitleLang, subs);
}

const _prefsKey = 'sushi_account_playback_pref_v1';

SushiAccountPlaybackPref _current = SushiAccountPlaybackPref.unset;
bool _loaded = false;
final List<void Function()> _playbackPrefWatchers = [];

/// Detail screens rebuild Play vs Request when sync replaces a stale on-disk answer.
void sushiWatchAccountPlaybackPref(void Function() onChange) {
  _playbackPrefWatchers.add(onChange);
}

void sushiUnwatchAccountPlaybackPref(void Function() onChange) {
  _playbackPrefWatchers.remove(onChange);
}

void _emitPlaybackPref(SushiAccountPlaybackPref next) {
  final changed = _current != next;
  _current = next;
  _loaded = true;
  if (!changed) return;
  for (final watcher in List<void Function()>.of(_playbackPrefWatchers)) {
    watcher();
  }
}

/// The last answers this device saw. Synchronous so a pick-list build can read it; callers that
/// build one have already awaited [sushiLoadAccountPlaybackPref] (via sushiReadVariantPreference).
SushiAccountPlaybackPref get sushiAccountPlaybackPref => _current;

Future<void> sushiLoadAccountPlaybackPref() async {
  if (_loaded) return;
  var next = SushiAccountPlaybackPref.unset;
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      next = SushiAccountPlaybackPref.fromWire(
        map['audio'] as String? ?? '',
        (map['maxHeight'] as num?)?.toInt() ?? 0,
        map['subtitleLang'] as String? ?? '',
        map['subs'] as String? ?? '',
      );
    }
  } catch (_) {
    next = SushiAccountPlaybackPref.unset;
  }
  _emitPlaybackPref(next);
}

/// Record what the server (or taste wizard) said. The in-memory answer always updates; a disk
/// write that fails only costs the next cold launch — never a reason to fail sync.
bool sushiSubtitleLangIsPersian(String lang) {
  final c = lang.trim().toLowerCase();
  return c.isEmpty || c == 'fa' || c == 'fas' || c == 'per' || c == 'farsi' || c == 'persian';
}

bool sushiSubtitleLangMatches(String code, String preferred) {
  final want = preferred.trim().toLowerCase();
  if (want.isEmpty) return true;
  final c = code.trim().toLowerCase();
  if (c.isEmpty) return false;
  final aliases = switch (want) {
    'fa' || 'fas' || 'per' || 'farsi' || 'persian' => {'fa', 'fas', 'per', 'farsi', 'persian'},
    'en' || 'eng' || 'english' => {'en', 'eng', 'english'},
    'ar' || 'ara' || 'arabic' => {'ar', 'ara', 'arabic'},
    'es' || 'spa' || 'spanish' => {'es', 'spa', 'spanish'},
    'fr' || 'fra' || 'fre' || 'french' => {'fr', 'fra', 'fre', 'french'},
    'de' || 'deu' || 'ger' || 'german' => {'de', 'deu', 'ger', 'german'},
    'tr' || 'tur' || 'turkish' => {'tr', 'tur', 'turkish'},
    'ru' || 'rus' || 'russian' => {'ru', 'rus', 'russian'},
    'pt' || 'por' || 'portuguese' => {'pt', 'por', 'portuguese'},
    'it' || 'ita' || 'italian' => {'it', 'ita', 'italian'},
    'ja' || 'jpn' || 'japanese' => {'ja', 'jpn', 'japanese'},
    'ko' || 'kor' || 'korean' => {'ko', 'kor', 'korean'},
    'zh' || 'zho' || 'chi' || 'chinese' => {'zh', 'zho', 'chi', 'chinese', 'zh-cn', 'zh-tw'},
    _ => {want},
  };
  return aliases.contains(c) || c.startsWith('$want-') || c.startsWith('${want}_');
}

/// SubDL language codes are uppercase ISO-ish (FA, EN, ES…).
String sushiSubtitleLangToSubdl(String lang) {
  final c = lang.trim().toLowerCase();
  if (sushiSubtitleLangIsPersian(c)) return 'FA';
  if (c.isEmpty) return 'FA';
  // SubDL uses 2-letter codes; map common 3-letter / aliases.
  return switch (c) {
    'eng' || 'english' => 'EN',
    'spa' || 'spanish' => 'ES',
    'fra' || 'fre' || 'french' => 'FR',
    'deu' || 'ger' || 'german' => 'DE',
    'tur' || 'turkish' => 'TR',
    'rus' || 'russian' => 'RU',
    'por' || 'portuguese' => 'PT',
    'ita' || 'italian' => 'IT',
    'jpn' || 'japanese' => 'JA',
    'kor' || 'korean' => 'KO',
    'zho' || 'chi' || 'chinese' || 'zh-cn' || 'zh-tw' => 'ZH',
    'ara' || 'arabic' => 'AR',
    _ => c.length >= 2 ? c.substring(0, 2).toUpperCase() : 'EN',
  };
}

/// sub-plus.ir language slug (prototype path).
String sushiSubtitleLangToSubplus(String lang) {
  if (sushiSubtitleLangIsPersian(lang)) return 'persian';
  final c = lang.trim().toLowerCase();
  return switch (c) {
    'en' || 'eng' || 'english' => 'english',
    'es' || 'spa' || 'spanish' => 'spanish',
    'fr' || 'fra' || 'fre' || 'french' => 'french',
    'de' || 'deu' || 'ger' || 'german' => 'german',
    'ar' || 'ara' || 'arabic' => 'arabic',
    'tr' || 'tur' || 'turkish' => 'turkish',
    'ru' || 'rus' || 'russian' => 'russian',
    _ => 'english',
  };
}

String sushiSubtitleLangDisplayEn(String lang) {
  final c = lang.trim().toLowerCase();
  if (sushiSubtitleLangIsPersian(c)) return 'Persian';
  return switch (c) {
    'en' || 'eng' || 'english' => 'English',
    'es' || 'spa' || 'spanish' => 'Spanish',
    'fr' || 'fra' || 'fre' || 'french' => 'French',
    'de' || 'deu' || 'ger' || 'german' => 'German',
    'ar' || 'ara' || 'arabic' => 'Arabic',
    'tr' || 'tur' || 'turkish' => 'Turkish',
    'ru' || 'rus' || 'russian' => 'Russian',
    'pt' || 'por' || 'portuguese' => 'Portuguese',
    'it' || 'ita' || 'italian' => 'Italian',
    'ja' || 'jpn' || 'japanese' => 'Japanese',
    'ko' || 'kor' || 'korean' => 'Korean',
    'zh' || 'zho' || 'chi' || 'chinese' || 'zh-cn' || 'zh-tw' => 'Chinese',
    _ => c.isEmpty ? 'Persian' : c.toUpperCase(),
  };
}

Future<void> sushiSaveAccountPlaybackPref(SushiAccountPlaybackPref pref) async {
  _emitPlaybackPref(pref);
  try {
    final prefs = await SharedPreferences.getInstance();
    if (pref.isUnset) {
      await prefs.remove(_prefsKey);
      return;
    }
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'audio': pref.audio == SushiAudioPref.unset ? '' : pref.audio.name,
        'maxHeight': pref.maxHeight,
        'subtitleLang': pref.subtitleLang,
        'subs': switch (pref.subs) {
          SushiSubsPref.on => 'on',
          SushiSubsPref.off => 'off',
          SushiSubsPref.unset => '',
        },
      }),
    );
  } catch (e) {
    debugPrint('[sushi] account playback pref not persisted: $e');
  }
}
