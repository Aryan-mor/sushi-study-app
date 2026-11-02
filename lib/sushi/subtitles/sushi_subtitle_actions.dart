import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/sushi/playback/sushi_persian_language.dart';
import 'package:fladder/sushi/sushi_account_playback_pref.dart';
import 'package:fladder/sushi/sushi_playback_subtitle.dart';
import 'package:fladder/sushi/sushi_title_subtitle_store.dart';
import 'package:fladder/sushi/sushi_stream_log.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_prefs_transport.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_subtitle_transport.dart';
import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/subtitles/sushi_gemini.dart';
import 'package:fladder/sushi/subtitles/sushi_opensubtitles.dart';
import 'package:fladder/sushi/subtitles/sushi_srt.dart';
import 'package:fladder/sushi/subtitles/sushi_subplus.dart';
import 'package:fladder/wrappers/media_control_wrapper.dart';

void _log(String phase, [Map<String, Object?> fields = const {}]) {
  SushiStreamLog.event('sushi_sub_$phase', fields: fields);
  developer.log('sushi_sub_$phase $fields', name: 'sushi.subs');
}

typedef SushiEpisodeRef = ({int season, int episode});

enum SushiActiveSubtitleKind { automatic, online, ai }

class SushiActiveSubtitle {
  const SushiActiveSubtitle({required this.kind, required this.label});
  final SushiActiveSubtitleKind kind;
  final String label;
  bool get auto => kind == SushiActiveSubtitleKind.automatic;
}

final sushiActiveSubtitleProvider = StateProvider<SushiActiveSubtitle?>((ref) => null);

T sushiRead<T>(Object src, ProviderListenable<T> provider) {
  if (src is WidgetRef) return src.read(provider);
  if (src is Ref) return src.read(provider);
  if (src is ProviderContainer) return src.read(provider);
  throw ArgumentError.value(src, 'src', 'want WidgetRef, Ref or ProviderContainer');
}

/// [MediaControlsWrapper.ref] is [videoPlayerProvider]'s Ref. Reading that
/// provider from inside [VideoPlayerNotifier] trips Riverpod's debug
/// "A provider cannot depend on itself" and kills Automatic on play.
MediaControlsWrapper sushiPlayer(Object src, {MediaControlsWrapper? player}) {
  return player ?? sushiRead(src, videoPlayerProvider);
}

bool sushiEmbeddedRowSelectable(WidgetRef ref) => ref.watch(sushiActiveSubtitleProvider) == null;

void sushiClearActiveSubtitle(WidgetRef ref) =>
    ref.read(sushiActiveSubtitleProvider.notifier).state = null;

/// Prototype ranking. For a TV [episode] the season match dominates (wrong-season packs sink);
/// then release-token overlap with the playing file's `qualityLabel` (doc 15 §4). DVDRip/XviD
/// against a 720p/1080p WEB-ish label is how Friends S3E12 got the wrong-episode cues.
List<SubplusPack> rankSubplusPacks(
  List<SubplusPack> packs, {
  String? query,
  String? year,
  SushiEpisodeRef? episode,
  String? sourceLabel,
}) {
  final sorted = sushiFilterSubplusPacks(
    packs,
    query: query,
    year: year,
    episode: episode,
  );
  sorted.sort((a, b) {
    int score(SubplusPack p) {
      var s = 0;
      if (episode != null) {
        s -= seasonMatchScore(p, episode.season) * 100;
        if (p.releases.any((r) {
          final se = parseSeasonEpisode(r);
          return se.season == episode.season && se.episode == episode.episode;
        })) {
          s -= 20;
        }
      }
      s -= sushiSubtitleSourceMatchScore(p, sourceLabel);
      if (year != null && year.isNotEmpty && p.year == year) s -= 2;
      if (p.releases.isNotEmpty) s -= 1;
      return s;
    }

    return score(a).compareTo(score(b));
  });
  return sorted;
}

/// Automatic (and English translate-source) try this many ranked packs when a ZIP has no
/// `.srt`/`.ass` (live miss: SubDL returned a pack whose zip was idx/sub or empty). Matches
/// the Online sheet's "top ~3" (doc 15 §7). Each miss is one `/subtitle_file` (R-UI-15).
const sushiAutoSubtitlePackAttempts = 3;

List<T> sushiSubtitlePackAttemptWindow<T>(List<T> ranked) {
  if (ranked.length <= sushiAutoSubtitlePackAttempts) return ranked;
  return ranked.sublist(0, sushiAutoSubtitlePackAttempts);
}

class SushiSubtitleOpResult {
  const SushiSubtitleOpResult({
    required this.ok,
    this.errorCode,
    this.label,
    this.fileNames,
    this.tag,
  });

  final bool ok;
  final String? errorCode;
  final String? label;
  final List<String>? fileNames;
  final String? tag;

  static const missingKey = SushiSubtitleOpResult(ok: false, errorCode: 'missing_key');
  static const noSource = SushiSubtitleOpResult(ok: false, errorCode: 'no_source');
  static const noResults = SushiSubtitleOpResult(ok: false, errorCode: 'no_results');
  static const failed = SushiSubtitleOpResult(ok: false, errorCode: 'failed');
  static const busy = SushiSubtitleOpResult(ok: false, errorCode: 'busy');
  // Result was superseded (user navigated to a different item mid-request) — not a
  // real failure, so callers should not surface a "failed" toast for this.
  static const stale = SushiSubtitleOpResult(ok: false, errorCode: 'stale');
  // Gemini call itself failed (network/HTTP/key-rejected), distinct from a source-fetch failure.
  static const translateServiceFailed = SushiSubtitleOpResult(ok: false, errorCode: 'translate_service_failed');
  // Every fallback model rejected the request with 429 RESOURCE_EXHAUSTED — the key's Gemini
  // billing/credits are depleted, not a transient rate limit. Retrying won't help until topped up.
  static const translateQuotaExceeded = SushiSubtitleOpResult(ok: false, errorCode: 'translate_quota_exceeded');
  // Translation succeeded but the player rejected applying it.
  static const applyFailed = SushiSubtitleOpResult(ok: false, errorCode: 'apply_failed');
}

/// Google's RESOURCE_EXHAUSTED for depleted prepaid credits (billing, account-wide) looks the
/// same as a per-model 429 in the exception message — distinguish it so the UI can point the
/// user at billing instead of suggesting a retry that can never succeed.
bool sushiGeminiQuotaExhausted(String message) =>
    message.contains('RESOURCE_EXHAUSTED') || message.contains('prepayment credits');

class SushiAiKeySetupInfo {
  const SushiAiKeySetupInfo({required this.deepLink, required this.telegramInstalled});
  final String deepLink;
  final bool telegramInstalled;
}

String? _lastSideloadedSrt;
String? _subtitleSessionItemId;
final Map<String, List<SubplusSubFile>> _packFiles = {};
bool _subtitleJobBusy = false;
int _subtitleJobId = 0;
int _subtitleCancelGen = 0;

/// Back / Esc on the loading dialog. In-flight Automatic, AI, and Online must not apply.
void sushiCancelSubtitleWork() {
  _subtitleCancelGen++;
  _translateGen++;
  _subtitleJobId++;
  _subtitleJobBusy = false;
  _log('cancel', {'gen': _subtitleCancelGen});
}

bool sushiSubtitleWasCancelled(int gen) => gen != _subtitleCancelGen;

int get sushiSubtitleCancelGen => _subtitleCancelGen;

String? sushiLastSideloadedSrt() => _lastSideloadedSrt;

void sushiRememberSideloadedSrt(String text) => _lastSideloadedSrt = text;

/// Drop the previous title's AI/Automatic sideload so it cannot land on this item minutes later.
/// [sessionKey] must change whenever playback actually restarts fresh — item id alone is not
/// enough: picking a different file of the SAME item (e.g. a different upload/quality from
/// outside the player) reopens the player with a session id equal to the last one, so the stale
/// "AI Persian" / "Automatic" active-subtitle marker survived and kept showing as on even though
/// nothing had been sideloaded onto this new file. Callers should key on item id + the specific
/// version/file id, not item id alone.
void sushiBeginPlaybackSubtitleSession(Object src, String sessionKey) {
  if (_subtitleSessionItemId == sessionKey) return;
  _subtitleSessionItemId = sessionKey;
  _translateGen++;
  _lastSideloadedSrt = null;
  _cachedTranslateEn = null;
  _cachedTranslateEnKey = null;
  _packFiles.clear();
  try {
    sushiRead(src, sushiActiveSubtitleProvider.notifier).state = null;
  } catch (_) {}
  _log('session_reset', {'sessionKey': sessionKey, 'gen': _translateGen});
}

Future<List<SubplusPack>> sushiSearchOnlinePacks(Object src) async {
  final title = sushiPlayingTitle(src);
  if (title == null) return const [];
  final cancelGen = _subtitleCancelGen;
  final client = SushiSubplusClient();
  try {
    await sushiLoadAccountPlaybackPref();
    final lang = sushiSubtitleLangToSubplus(sushiAccountPlaybackPref.subtitleLangOrFa);
    _log('search_start', {'q': title, 'lang': lang});
    final packs = rankSubplusPacks(
      await client.search(title, lang: lang),
      query: title,
      year: sushiPlayingYear(src),
      episode: sushiPlayingEpisode(src),
      sourceLabel: sushiPlayingSourceLabel(src),
    );
    _log('search_done', {'packs': packs.length, 'lang': lang});
    if (sushiSubtitleWasCancelled(cancelGen)) return const [];
    return packs;
  } finally {
    client.close();
  }
}

Future<SushiSubtitleOpResult> sushiDownloadOnlinePack({
  required Object src,
  required String tag,
  required String fileName,
  MediaControlsWrapper? player,
}) async {
  final cancelGen = _subtitleCancelGen;
  final p = sushiPlayer(src, player: player);
  final client = SushiSubplusClient();
  try {
    var files = _packFiles[tag];
    if (files == null) {
      files = await client.fetchSubs(tag);
      _packFiles[tag] = files;
    }
    if (files.isEmpty) return SushiSubtitleOpResult.noResults;
    if (fileName.isEmpty) {
      if (files.length == 1) {
        if (sushiSubtitleWasCancelled(cancelGen)) return SushiSubtitleOpResult.stale;
        return _applyOnlineAndRemember(src, p, files.first, labelPrefix: files.first.name);
      }
      final episode = sushiPlayingEpisode(src);
      if (episode != null) {
        final pick = pickEpisodeFile(files, episode.season, episode.episode);
        if (pick != null) {
          if (sushiSubtitleWasCancelled(cancelGen)) return SushiSubtitleOpResult.stale;
          return _applyOnlineAndRemember(src, p, pick, labelPrefix: pick.name);
        }
      }
      return SushiSubtitleOpResult(
        ok: false,
        errorCode: 'need_pick',
        tag: tag,
        fileNames: files.map((f) => f.name).toList(),
      );
    }
    final match = files.where((f) => f.name == fileName);
    if (match.isEmpty) return SushiSubtitleOpResult.noResults;
    if (sushiSubtitleWasCancelled(cancelGen)) return SushiSubtitleOpResult.stale;
    return _applyOnlineAndRemember(src, p, match.first, labelPrefix: match.first.name);
  } catch (e, st) {
    _log('download_error', {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' | ')});
    return SushiSubtitleOpResult.failed;
  } finally {
    client.close();
  }
}

bool sushiSubtitleOpShouldFallback(SushiSubtitleOpResult r) =>
    !r.ok && r.errorCode != 'busy' && r.errorCode != 'stale';

Future<SushiSubtitleOpResult> sushiRunAutoLoad(
  Object src, {
  MediaControlsWrapper? player,
  bool remember = false,
}) async {
  if (_subtitleJobBusy) {
    _log('auto_busy');
    return SushiSubtitleOpResult.busy;
  }
  _subtitleJobBusy = true;
  final job = ++_subtitleJobId;
  final cancelGen = _subtitleCancelGen;
  final startedFor = _subtitleSessionItemId;
  final choiceGen = remember ? sushiBeginManualSubtitleChoice() : null;
  try {
    // Skip-through: wait out a hop before touching gomobile. FetchSmallDocument holding the
    // JNI gate during UploadGetFile + a gotd FileReference alias crashed with
    // `bulkBarrierPreWrite: unaligned arguments` (Friends S3, 2026-09-21).
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (startedFor != _subtitleSessionItemId || sushiSubtitleWasCancelled(cancelGen)) {
      _log('auto_stale_before_fetch');
      return SushiSubtitleOpResult.stale;
    }
    final p = sushiPlayer(src, player: player);
    // subdl is the production path (doc 15 §7). sub-plus.ir is a prototype with no SLA (doc 15
    // §6) and has been returning HTTP 500 — try it only after subdl misses.
    // Cache + search use the user's taste subtitle_lang (not hardcoded Persian).
    await sushiLoadAccountPlaybackPref();
    final pref = sushiAccountPlaybackPref;
    final subdlLang = pref.subdlLangCode;
    final subplusLang = sushiSubtitleLangToSubplus(pref.subtitleLangOrFa);
    var pick = await _fetchSubdlFile(src, lang: subdlLang);
    if (startedFor != _subtitleSessionItemId || sushiSubtitleWasCancelled(cancelGen)) {
      _log('auto_stale_after_fetch');
      return SushiSubtitleOpResult.stale;
    }
    pick ??= await _fetchSubplusFile(src, lang: subplusLang);
    if (startedFor != _subtitleSessionItemId || sushiSubtitleWasCancelled(cancelGen)) {
      _log('auto_stale_after_fetch');
      return SushiSubtitleOpResult.stale;
    }
    if (pick == null) {
      _log('auto_no_results');
      return SushiSubtitleOpResult.noResults;
    }
    if (sushiSubtitleWasCancelled(cancelGen)) return SushiSubtitleOpResult.stale;
    final applied = await _applyFile(
      src,
      p,
      pick.file,
      auto: true,
      labelPrefix: pick.label,
    );
    if (remember && applied.ok && choiceGen != null && !sushiSubtitleWasCancelled(cancelGen)) {
      await _rememberPlayingSubtitle(src, SushiTitleSubtitleKind.automatic, choiceGen: choiceGen);
    }
    return applied;
  } finally {
    if (_subtitleJobId == job) _subtitleJobBusy = false;
  }
}

/// Playback-start chain: Automatic (online) → AI (if Gemini key) → muxed Farsi soft.
/// Hard-sub callers must not enter this pipeline (choice is Off).
Future<SushiSubtitleOpResult> sushiRunStartSubtitlePipeline(
  Object src, {
  MediaControlsWrapper? player,
  required bool hasPersianSoft,
  bool allowAiFallback = true,
  PlaybackModel? model,
}) async {
  final auto = await sushiRunAutoLoad(src, player: player);
  if (!sushiSubtitleOpShouldFallback(auto)) return auto;

  if (allowAiFallback && await sushiHasGeminiApiKey()) {
    final ai = await sushiRunTranslateToPersian(src, forceKeyRefresh: false, player: player);
    _log('start_ai_fallback', {'ok': ai.ok, 'error': ai.errorCode});
    if (!sushiSubtitleOpShouldFallback(ai)) return ai;
  }

  if (hasPersianSoft) {
    final applied = await sushiApplyPreferredSoftFallback(src, player: player, model: model);
    if (applied) {
      _log('start_soft_fallback');
      return const SushiSubtitleOpResult(ok: true, label: 'Soft sub');
    }
  }
  return auto;
}

Future<bool> sushiApplyPersianSoftFallback(
  Object src, {
  MediaControlsWrapper? player,
  PlaybackModel? model,
}) =>
    sushiApplyPreferredSoftFallback(src, player: player, model: model);

Future<bool> sushiApplyPreferredSoftFallback(
  Object src, {
  MediaControlsWrapper? player,
  PlaybackModel? model,
}) async {
  final p = sushiPlayer(src, player: player);
  final playback = model ?? sushiRead(src, playBackModel);
  if (playback == null) return false;
  await sushiLoadAccountPlaybackPref();
  final want = sushiAccountPlaybackPref.subtitleLangOrFa;
  final index = sushiPreferredLangStreamIndex(playback.subStreams, want) ??
      (sushiSubtitleLangIsPersian(want) ? sushiPreferredPersianStreamIndex(playback.subStreams) : null);
  if (index == null) return false;
  final track = playback.subStreams?.firstWhereOrNull((s) => s.index == index);
  if (track == null || !sushiSubtitleTrackIsPlayable(track)) return false;
  final newModel = await playback.setSubtitle(track, p);
  if (newModel == null) return false;
  sushiRead(src, playBackModel.notifier).update((_) => newModel);
  try {
    sushiRead(src, sushiActiveSubtitleProvider.notifier).state = null;
  } catch (_) {}
  return true;
}

Future<SushiSubtitleOpResult> sushiRunTranslateToPersian(
  Object src, {
  bool forceKeyRefresh = true,
  MediaControlsWrapper? player,
  bool remember = false,
}) async {
  if (_subtitleJobBusy) return SushiSubtitleOpResult.busy;
  _subtitleJobBusy = true;
  final job = ++_subtitleJobId;
  final cancelGen = _subtitleCancelGen;
  final choiceGen = remember ? sushiBeginManualSubtitleChoice() : null;
  try {
    return await _sushiRunTranslateToPersianBody(
      src,
      forceKeyRefresh: forceKeyRefresh,
      player: player,
      remember: remember,
      choiceGen: choiceGen,
      cancelGen: cancelGen,
    );
  } finally {
    if (_subtitleJobId == job) _subtitleJobBusy = false;
  }
}

Future<SushiSubtitleOpResult> _sushiRunTranslateToPersianBody(
  Object src, {
  required bool forceKeyRefresh,
  MediaControlsWrapper? player,
  bool remember = false,
  int? choiceGen,
  int? cancelGen,
}) async {
  final key = await sushiGeminiApiKey(force: forceKeyRefresh);
  if (key == null || key.isEmpty) return SushiSubtitleOpResult.missingKey;

  // Never reuse a prior sideload — Automatic/Online can cache the wrong same-title pack
  // (2017 *The Breadwinner* while TMDB 1440050 is the 2026 film).
  final source = await _fetchTranslateSourceSrt(src);
  if (source == null || source.isEmpty) return SushiSubtitleOpResult.noSource;

  final cues = sushiParseSrt(source);
  if (cues.isEmpty) return SushiSubtitleOpResult.noSource;

  final gemini = SushiGeminiClient();
  final p = sushiPlayer(src, player: player);
  final gen = ++_translateGen;
  final startedFor = _subtitleSessionItemId;
  try {
    var at = p.lastState?.position ?? Duration.zero;
    try {
      final media = sushiRead(src, mediaPlaybackProvider);
      if (media.position > at) at = media.position;
    } catch (_) {}
    try {
      final start = await sushiRead(src, playBackModel)?.startDuration();
      if (start != null && start > at) at = start;
    } catch (_) {}
    final window = sushiSplitCuesAroundPlayback(cues, at);
    _log('translate_start', {
      'cues': cues.length,
      'now': window.now.length,
      'later': window.later.length,
      'posMs': at.inMilliseconds,
    });
    await sushiLoadAccountPlaybackPref();
    final pref = sushiAccountPlaybackPref;
    final targetLang = pref.subtitleLangOrFa;
    final label = 'AI ${pref.subtitleLangDisplayEn}';
    final nowFa = await gemini.translateCues(window.now, key, targetLang: targetLang);
    if (gen != _translateGen || startedFor != _subtitleSessionItemId) {
      _log('translate_stale', {'gen': gen, 'currentGen': _translateGen});
      return SushiSubtitleOpResult.stale;
    }
    if (cancelGen != null && sushiSubtitleWasCancelled(cancelGen)) {
      _log('translate_stale', {'reason': 'cancel'});
      return SushiSubtitleOpResult.stale;
    }
    sushiRememberSideloadedSrt(nowFa);
    final applied = await p.setSubtitleFromText(nowFa, title: label, language: targetLang);
    if (!applied) {
      _log('translate_apply_failed', {'chars': nowFa.length});
      return SushiSubtitleOpResult.applyFailed;
    }
    sushiRead(src, sushiActiveSubtitleProvider.notifier).state =
        SushiActiveSubtitle(kind: SushiActiveSubtitleKind.ai, label: label);
    if (remember && choiceGen != null) {
      await _rememberPlayingSubtitle(src, SushiTitleSubtitleKind.ai, choiceGen: choiceGen);
    }
    _log('translate_applied', {'chars': nowFa.length, 'phase': 'window', 'cues': window.now.length, 'lang': targetLang});
    if (window.later.isNotEmpty) {
      unawaited(_translateRestInBackground(
        gen: gen,
        startedFor: startedFor,
        player: p,
        key: key,
        targetLang: targetLang,
        label: label,
        nowCues: sushiParseSrt(nowFa),
        later: window.later,
      ));
    }
    return SushiSubtitleOpResult(ok: true, label: label);
  } on SushiGeminiException catch (e, st) {
    _log('translate_service_error', {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' | ')});
    if (sushiGeminiQuotaExhausted(e.message)) return SushiSubtitleOpResult.translateQuotaExceeded;
    return SushiSubtitleOpResult.translateServiceFailed;
  } catch (e, st) {
    _log('translate_error', {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' | ')});
    return SushiSubtitleOpResult.failed;
  } finally {
    gemini.close();
  }
}

int _translateGen = 0;

Future<void> _translateRestInBackground({
  required int gen,
  required String? startedFor,
  required MediaControlsWrapper player,
  required String key,
  required String targetLang,
  required String label,
  required List<SushiSrtCue> nowCues,
  required List<SushiSrtCue> later,
}) async {
  final gemini = SushiGeminiClient();
  try {
    final rest = await gemini.translateCues(later, key, targetLang: targetLang, concurrency: 3);
    if (gen != _translateGen || startedFor != _subtitleSessionItemId) return;
    final merged = sushiMergeSrtByTiming(nowCues, sushiParseSrt(rest));
    sushiRememberSideloadedSrt(merged);
    final applied = await player.setSubtitleFromText(merged, title: label, language: targetLang);
    if (!applied) {
      _log('translate_apply_failed', {'chars': merged.length, 'phase': 'full'});
      return;
    }
    _log('translate_applied', {'chars': merged.length, 'phase': 'full', 'lang': targetLang});
  } catch (e, st) {
    _log('translate_bg_error', {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' | ')});
  } finally {
    gemini.close();
  }
}

/// English first (OpenSubtitles TMDB id, then sub-plus). Never Persian — that was the 2017
/// same-title collision, then Gemini rewrote Farsi into Farsi. Gemini output is what gets
/// sideloaded.
String? _cachedTranslateEn;
String? _cachedTranslateEnKey;

Future<String?> _fetchTranslateSourceSrt(Object src) async {
  final cacheKey = '${sushiPlayingTitle(src) ?? ''}|${sushiPlayingYear(src) ?? ''}|${sushiPlayingTmdbId(src) ?? ''}';
  final cached = _cachedTranslateEn;
  if (cached != null && cached.isNotEmpty && _cachedTranslateEnKey == cacheKey) {
    _log('translate_source', {'via': 'memory', 'chars': cached.length});
    return cached;
  }
  // The file's own muxed/attached track (any non-Persian language) is a guaranteed timing
  // match for THIS exact media source — try it before searching external catalogs, which can
  // return a mistimed or wrong-cut file (see the Forced-subtitle bug this was added alongside).
  final embedded = await _fetchEmbeddedTranslateSourceSrt(src);
  if (embedded != null && embedded.isNotEmpty) {
    _cachedTranslateEn = embedded;
    _cachedTranslateEnKey = cacheKey;
    sushiRememberSideloadedSrt(embedded);
    _log('translate_source', {'via': 'embedded', 'chars': embedded.length});
    return embedded;
  }
  final os = await _fetchOpenSubtitlesEnglish(src);
  if (os != null && os.isNotEmpty) {
    _cachedTranslateEn = os;
    _cachedTranslateEnKey = cacheKey;
    sushiRememberSideloadedSrt(os);
    _log('translate_source', {'via': 'opensubtitles_en', 'chars': os.length});
    return os;
  }
  final subdlEn = await _fetchSubdlFile(src, lang: 'english');
  if (subdlEn != null) {
    _cachedTranslateEn = subdlEn.file.text;
    _cachedTranslateEnKey = cacheKey;
    sushiRememberSideloadedSrt(subdlEn.file.text);
    _log('translate_source', {'via': 'subdl_en', 'chars': subdlEn.file.text.length, 'label': subdlEn.label});
    return subdlEn.file.text;
  }
  final en = await _fetchSubplusFile(src, lang: 'english');
  if (en != null) {
    _cachedTranslateEn = en.file.text;
    _cachedTranslateEnKey = cacheKey;
    sushiRememberSideloadedSrt(en.file.text);
    _log('translate_source', {'via': 'subplus_en', 'chars': en.file.text.length, 'label': en.label});
    return en.file.text;
  }
  return null;
}

/// Bitmap/image subtitle codecs Jellyfin can't hand back as text — a `.srt` fetch for one of
/// these would come back empty or garbage, not a translatable transcript.
const _sushiImageSubtitleCodecs = {
  'pgssub',
  'dvdsub',
  'dvd_subtitle',
  'dvbsub',
  'dvb_subtitle',
  'vobsub',
  'xsub',
  'hdmv_pgs_subtitle',
};

/// Picks a text-based, non-Persian, non-Off track with a fetchable delivery URL — preferring
/// English when more than one language is muxed in. Persian is excluded because translating it
/// would be Farsi-to-Farsi (doc 15 §12's "2017 same-title collision" case); any other language
/// works since Gemini's prompt doesn't pin a source language.
SubStreamModel? _pickEmbeddedTranslateSource(List<SubStreamModel>? subStreams) {
  if (subStreams == null || subStreams.isEmpty) return null;
  final candidates = subStreams.where((s) {
    if (s.index == -1) return false;
    if ((s.url ?? '').trim().isEmpty) return false;
    if (_sushiImageSubtitleCodecs.contains(s.codec.trim().toLowerCase())) return false;
    if (SushiPersianLanguage.isPersianLanguage(s.language) ||
        SushiPersianLanguage.isPersianLanguage(s.displayTitle)) {
      return false;
    }
    return true;
  }).toList();
  if (candidates.isEmpty) return null;
  final english = candidates.firstWhereOrNull(
    (s) => sushiIsEnglishLanguage(s.language) || s.displayTitle.toLowerCase().contains('english'),
  );
  return english ?? candidates.first;
}

/// The file's own muxed/attached subtitle, fetched straight from the Jellyfin server (same
/// `.srt` delivery URL the player itself would use) — no title search, so no risk of matching
/// the wrong release or a Forced-only file.
Future<String?> _fetchEmbeddedTranslateSourceSrt(Object src) async {
  final subStreams = sushiRead(src, playBackModel)?.subStreams;
  final picked = _pickEmbeddedTranslateSource(subStreams);
  final url = picked?.url?.trim();
  if (picked == null || url == null || url.isEmpty) return null;
  try {
    final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    var text = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    text = text.trim();
    if (sushiParseSrt(text).isEmpty) return null;
    return text;
  } catch (e) {
    _log('embedded_source_error', {'error': e.toString(), 'lang': picked.language});
    return null;
  }
}

Future<({SubplusSubFile file, String label})?> _fetchSubplusFile(Object src, {required String lang}) async {
  final title = sushiPlayingTitle(src);
  if (title == null) return null;
  final year = sushiPlayingYear(src);
  final episode = sushiPlayingEpisode(src);
  final client = SushiSubplusClient();
  try {
    _log('subplus_fetch', {'lang': lang, 'title': title, 'year': year ?? ''});
    final raw = await client.search(title, lang: lang);
    final packs = rankSubplusPacks(
      raw,
      query: title,
      year: year,
      episode: episode,
      sourceLabel: sushiPlayingSourceLabel(src),
    );
    if (packs.isEmpty) {
      _log('subplus_fetch_empty', {'lang': lang, 'title': title, 'year': year ?? '', 'raw': raw.length});
      return null;
    }
    final attempts = sushiSubtitlePackAttemptWindow(packs);
    for (var i = 0; i < attempts.length; i++) {
      final pack = attempts[i];
      final List<SubplusSubFile> subs;
      try {
        subs = await client.fetchSubs(pack.tag);
      } catch (e) {
        _log('subplus_try_miss', {'i': i, 'pack': pack.title, 'error': e.toString()});
        continue;
      }
      _packFiles[pack.tag] = subs;
      final pick = episode == null
          ? pickMovieSubFile(subs)
          : pickEpisodeFile(subs, episode.season, episode.episode);
      if (pick == null) {
        _log('subplus_try_miss', {'i': i, 'pack': pack.title, 'reason': 'no_srt'});
        continue;
      }
      _log('subplus_pick', {
        'lang': lang,
        'pack': pack.title,
        'packYear': pack.year,
        'imdb': pack.imdb,
        'file': pick.name,
        'attempt': i,
      });
      return (file: pick, label: '${pack.title} · ${pick.name}');
    }
    _log('subplus_fetch_empty', {'lang': lang, 'title': title, 'reason': 'all_packs_empty'});
    return null;
  } catch (e, st) {
    _log('subplus_fetch_error', {
      'lang': lang,
      'error': e.toString(),
      'stack': st.toString().split('\n').take(3).join(' | '),
    });
    return null;
  } finally {
    client.close();
  }
}

/// Release family named by a quality label or a subtitle release name. A source word
/// (dvd / web / bluray / hdtv / telesync / cam) wins over softsub/hardsub. Empty when the
/// label doesn't say.
String sushiSubtitleCutType(String label) {
  final s = label.toLowerCase();
  if (s.contains('dvd')) return 'dvd';
  if (s.contains('webrip') ||
      s.contains('web-dl') ||
      s.contains('webdl') ||
      s.contains('web.dl') ||
      RegExp(r'(^|[^a-z])web([^a-z]|$)').hasMatch(s)) {
    return 'web';
  }
  if (s.contains('bluray') || s.contains('blu-ray') || s.contains('bdrip') || s.contains('brrip')) {
    return 'bluray';
  }
  if (s.contains('hdtv')) return 'hdtv';
  if (s.contains('telesync') || RegExp(r'(^|[^a-z])hdts([^a-z]|$)').hasMatch(s)) {
    return 'telesync';
  }
  if (s.contains('camrip') ||
      s.contains('cam-rip') ||
      s.contains('hdcam') ||
      s.contains('hdtc') ||
      RegExp(r'(^|[^a-z])cam([^a-z]|$)').hasMatch(s)) {
    return 'cam';
  }
  if (s.contains('softsub') || s.contains('soft sub') || s.contains('سافت')) return 'softsub';
  if (s.contains('hardsub') || s.contains('hard sub') || s.contains('هارد')) return 'hardsub';
  return '';
}

/// Packs whose cut matches [wantType] come first. No match leaves [ranked] unchanged so a
/// SoftSub file can still try the closest BluRay/WEB timeline.
List<SubplusPack> sushiPreferSubtitleCut(List<SubplusPack> ranked, String wantType) {
  if (wantType.isEmpty || ranked.length < 2) return ranked;
  final same = <SubplusPack>[];
  final rest = <SubplusPack>[];
  for (final p in ranked) {
    final blob = '${p.title} ${p.releases.join(' ')}';
    if (sushiSubtitleCutType(blob) == wantType) {
      same.add(p);
    } else {
      rest.add(p);
    }
  }
  if (same.isEmpty) return ranked;
  return [...same, ...rest];
}

/// End of the last cue, in seconds. 0 when [text] has no SRT/ASS timestamp.
int sushiSubtitleTimelineSeconds(String text) {
  final re = RegExp(r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})');
  var maxEnd = 0;
  for (final line in text.split('\n')) {
    final low = line.toLowerCase();
    if (!line.contains('-->') && !low.contains('dialogue:')) continue;
    final matches = re.allMatches(line).toList();
    if (matches.isEmpty) continue;
    final m = matches.last;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    final sec = int.parse(m.group(3)!);
    var frac = m.group(4)!;
    while (frac.length < 3) {
      frac = '${frac}0';
    }
    final ms = int.parse(frac.substring(0, 3));
    final end = h * 3600 + min * 60 + sec;
    final whole = ms >= 500 ? end + 1 : end;
    if (whole > maxEnd) maxEnd = whole;
  }
  return maxEnd;
}

int sushiPlayingDurationSeconds(Object src) {
  try {
    final d = sushiRead(src, mediaPlaybackProvider).duration;
    if (d > Duration.zero) return d.inSeconds;
  } catch (_) {}
  final rt = sushiRead(src, playBackModel)?.item.overview.runTime;
  if (rt != null && rt > Duration.zero) return rt.inSeconds;
  return 0;
}

/// Second subtitle provider (doc 15 §7), server-proxied so subdl's key never reaches this device.
/// Same return shape as [_fetchSubplusFile]. Search matches tmdb_id; each hit is a ZIP that
/// *should* contain one .srt/.ass. Empty zips (`zip has no .srt/.ass files`) are an ERR, so
/// Automatic walks the top [sushiAutoSubtitlePackAttempts] ranked tags. `tag` is prefixed
/// `subdl:` so a later fetch of the same pick can tell providers apart.
Future<({SubplusSubFile file, String label})?> _fetchSubdlFile(Object src, {required String lang}) async {
  final tmdbId = sushiPlayingTmdbId(src);
  if (tmdbId == null) return null;
  final title = sushiPlayingTitle(src);
  final episode = sushiPlayingEpisode(src);
  // `lang` may be SubDL code (FA/EN), ISO (fa/en), or sub-plus slug (persian/english).
  final subdlLang = lang.length <= 3 && lang == lang.toUpperCase()
      ? lang
      : sushiSubtitleLangToSubdl(lang == 'english' ? 'en' : lang);
  try {
    final sourceLabel = sushiPlayingSourceLabel(src) ?? '';
    final wantSeconds = sushiPlayingDurationSeconds(src);
    final wantMin = wantSeconds <= 0 ? 0 : (wantSeconds / 60).round();
    _log('subdl_fetch', {
      'lang': lang,
      'subdlLang': subdlLang,
      'title': title ?? '',
      'tmdbId': tmdbId,
      'durationMin': wantMin,
      'source': sourceLabel,
    });
    final res = await sushiFetchSubtitles(
      tmdbId: tmdbId,
      kind: episode != null ? 2 : 1,
      seasonNo: episode?.season ?? 0,
      episodeNo: episode?.episode ?? 0,
      lang: subdlLang,
      durationMin: wantMin,
      sourceLabel: sourceLabel,
    );
    if (res == null || res.packs.isEmpty) {
      _log('subdl_fetch_empty', {'lang': lang, 'title': title ?? ''});
      return null;
    }
    final packs = res.packs
        .map((p) => SubplusPack(
              tag: 'subdl:${p.tag}',
              title: p.releaseName,
              imdb: '',
              year: '',
              series: episode != null,
              translator: p.translator,
              releases: p.releases,
              poster: '',
            ))
        .toList();
    // No query filter here: subdl already matched on tmdb_id server-side, an exact-title
    // guarantee subplus's fuzzy multi-title search doesn't have. Re-applying the substring
    // title filter here only risks dropping every pack when a release name (a raw scene
    // filename, e.g. "Ride.or.Die.2021.1080p...") doesn't happen to contain the query text.
    final ranked = rankSubplusPacks(
      packs,
      episode: episode,
      sourceLabel: sourceLabel,
    );
    if (ranked.isEmpty) {
      _log('subdl_fetch_empty', {'lang': lang, 'title': title ?? '', 'reason': 'no_rank_match'});
      return null;
    }
    final attempts = sushiSubtitlePackAttemptWindow(
      sushiPreferSubtitleCut(ranked, sushiSubtitleCutType(sourceLabel)),
    );
    final kind = episode != null ? 2 : 1;
    final seasonNo = episode?.season ?? 0;
    final episodeNo = episode?.episode ?? 0;
    // locator must match exactly what the server stamps as the copy's caption
    // (api.subtitleLocator, be/internal/app/api/subtitle.go) — arm the delivery waiter for it
    // *before* triggering the copy below, same ordering sushi_tdlib_playback_resolver.dart uses
    // for video, so the live push can never land before something is listening for it.
    final locator = 'sub_${tmdbId}_${kind}_${seasonNo}_${episodeNo}_$subdlLang';
    var bestText = '';
    var bestLabel = '';
    var bestExt = '.srt';
    var bestDelta = 1 << 30;
    for (var i = 0; i < attempts.length; i++) {
      final top = attempts[i];
      final rawTag = top.tag.startsWith('subdl:') ? top.tag.substring('subdl:'.length) : top.tag;
      _log('subdl_try', {'lang': lang, 'i': i, 'n': attempts.length, 'pack': top.title});
      // Re-arm per pack. Packs share one caption, and the previous fetch drops its waiter
      // when it returns. The copy for this attempt must not land with nobody listening.
      await sushiArmDeliveryWaiter(locator);
      final fileRes = await sushiFetchSubtitleFile(tag: rawTag);
      if (fileRes == null) {
        _log('subdl_try_miss', {'i': i, 'reason': 'no_delivery_ref'});
        continue;
      }
      // The server placed a fresh copy in this session's own chat, round-robinned across delivery
      // bots — the reference alone (doc 15 §7) never carries the text, since a real subtitle
      // routinely exceeds the wire protocol's per-message size limit. fileRes.messageId is the
      // Bot API's own chat-scoped counter, NOT this reader account's MTProto message-id space, so
      // it cannot be looked up directly (that mismatch is what produced OX_DM_STALE / wrong-file
      // reads before this fix) — fetchSmallDocument resolves the real id from the live push instead,
      // exactly like a fresh (0/0) video delivery does.
      final text = await sushiFetchSmallDocument(
        botId: fileRes.botId,
        messageId: fileRes.messageId,
        locator: locator,
      );
      if (text.isEmpty) {
        _log('subdl_try_miss', {'i': i, 'reason': 'empty_document'});
        continue;
      }
      final cueSeconds = sushiSubtitleTimelineSeconds(text);
      final delta = wantSeconds <= 0 || cueSeconds <= 0 ? 0 : (cueSeconds - wantSeconds).abs();
      _log('subdl_try_len', {'i': i, 'cueSec': cueSeconds, 'wantSec': wantSeconds, 'delta': delta});
      if (bestText.isEmpty || delta < bestDelta) {
        bestText = text;
        bestLabel = top.title;
        bestExt = fileRes.ext.isNotEmpty ? fileRes.ext : '.srt';
        bestDelta = delta;
      }
    }
    if (bestText.isEmpty) {
      _log('subdl_fetch_error', {'lang': lang, 'reason': 'all_packs_empty', 'tried': attempts.length});
      return null;
    }
    _log('subdl_pick', {'lang': lang, 'pack': bestLabel, 'deltaSec': bestDelta});
    return (
      file: SubplusSubFile(name: bestLabel, ext: bestExt, text: bestText),
      label: bestLabel,
    );
  } catch (e, st) {
    _log('subdl_fetch_error', {
      'lang': lang,
      'error': e.toString(),
      'stack': st.toString().split('\n').take(3).join(' | '),
    });
    return null;
  }
}

Future<String?> _fetchOpenSubtitlesEnglish(Object src) async {
  final title = sushiPlayingTitle(src);
  if (title == null) return null;
  final client = SushiOpenSubtitlesClient();
  if (!client.configured) {
    _log('opensubs_skip', {'reason': 'no_consumer_key'});
    return null;
  }
  try {
    final text = await client.fetchEnglishSrt(
      title: title,
      tmdbId: sushiPlayingTmdbId(src),
      episode: sushiPlayingEpisode(src),
      year: sushiPlayingYear(src),
    );
    return text;
  } catch (e, st) {
    _log('opensubs_error', {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' | ')});
    return null;
  } finally {
    client.close();
  }
}

Future<SushiAiKeySetupInfo> sushiAiKeySetupInfo() async {
  final url = SushiConfig.mainBotAppCodeUrl('ai_key');
  var installed = true;
  try {
    installed = await canLaunchUrl(
      Uri.parse('tg://resolve?domain=${SushiConfig.mainBotUsername}'),
    );
  } catch (_) {
    installed = true;
  }
  return SushiAiKeySetupInfo(deepLink: url, telegramInstalled: installed);
}

String? sushiPlayingTitle(Object src) {
  final name = sushiRead(src, playBackModel)?.item.title.trim() ?? '';
  return name.isEmpty ? null : name;
}

/// Playing file's `qualityLabel` (VersionStream.name). Empty when nothing is up.
String? sushiPlayingSourceLabel(Object src) {
  final name = sushiRead(src, playBackModel)?.mediaStreams?.currentVersionStream?.name.trim() ?? '';
  return name.isEmpty ? null : name;
}

String? sushiPlayingYear(Object src) {
  final overview = sushiRead(src, playBackModel)?.item.overview;
  return (overview?.yearAired ?? overview?.productionYear)?.toString();
}

SushiEpisodeRef? sushiPlayingEpisode(Object src) {
  final item = sushiRead(src, playBackModel)?.item;
  if (item is EpisodeModel && item.season > 0 && item.episode > 0) {
    return (season: item.season, episode: item.episode);
  }
  return null;
}

int? sushiPlayingTmdbId(Object src) {
  final item = sushiRead(src, playBackModel)?.item;
  if (item == null) return null;
  if (item is EpisodeModel) {
    return sushiTmdbIdFromItemId(item.parentId ?? '') ?? sushiTmdbIdFromItemId(item.id);
  }
  return sushiTmdbIdFromItemId(item.id);
}

Future<void> _rememberPlayingSubtitle(
  Object src,
  SushiTitleSubtitleKind kind, {
  required int choiceGen,
}) async {
  try {
    final item = sushiRead(src, playBackModel)?.item;
    if (item == null) return;
    await sushiWriteTitleSubtitle(item, SushiTitleSubtitleMemory(kind: kind), choiceGen: choiceGen);
  } catch (e) {
    _log('remember_skip', {'kind': kind.name, 'error': e.toString()});
  }
}

Future<SushiSubtitleOpResult> _applyOnlineAndRemember(
  Object src,
  MediaControlsWrapper player,
  SubplusSubFile file, {
  required String labelPrefix,
}) async {
  final choiceGen = sushiBeginManualSubtitleChoice();
  final applied = await _applyFile(src, player, file, auto: false, labelPrefix: labelPrefix);
  if (applied.ok) {
    await _rememberPlayingSubtitle(src, SushiTitleSubtitleKind.automatic, choiceGen: choiceGen);
  }
  return applied;
}

Future<SushiSubtitleOpResult> _applyFile(
  Object src,
  MediaControlsWrapper player,
  SubplusSubFile file, {
  required bool auto,
  required String labelPrefix,
}) async {
  sushiRememberSideloadedSrt(file.text);
  await sushiLoadAccountPlaybackPref();
  final lang = sushiAccountPlaybackPref.subtitleLangOrFa;
  final applied = await player.setSubtitleFromText(file.text, title: labelPrefix, language: lang);
  if (!applied) {
    _log('apply_failed', {'chars': file.text.length, 'label': labelPrefix, 'auto': auto, 'lang': lang});
    return SushiSubtitleOpResult.applyFailed;
  }
  sushiRead(src, sushiActiveSubtitleProvider.notifier).state = SushiActiveSubtitle(
    kind: auto ? SushiActiveSubtitleKind.automatic : SushiActiveSubtitleKind.online,
    label: labelPrefix,
  );
  _log('applied', {'chars': file.text.length, 'label': labelPrefix, 'auto': auto, 'lang': lang});
  return SushiSubtitleOpResult(ok: true, label: labelPrefix);
}
