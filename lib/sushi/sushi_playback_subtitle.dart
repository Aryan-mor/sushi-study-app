import 'package:collection/collection.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/sushi/playback/sushi_persian_language.dart';
import 'package:fladder/sushi/sushi_account_playback_pref.dart';

/// True when MediaSource / version label indicates burned-in (hard) subtitles.
///
/// `زیرنویس چسبیده` is only a claim. The container decides: a playable srt/ass track means
/// softsub; no playable track plus that claim means hardsub.
bool sushiMediaSourceLooksHardSub(String? mediaSourceName, {List<SubStreamModel>? subStreams}) {
  // Catalog `sub_langs` stubs have an index and no codec. That is still a muxed track.
  if (subStreams != null && subStreams.any((s) => s.index != -1)) {
    return false;
  }
  final blob = (mediaSourceName ?? '').toLowerCase().trim();
  if (blob.isEmpty) return false;
  final explicit = RegExp(r'hard[\s_-]*sub').hasMatch(blob) ||
      blob.contains('hardsub') ||
      blob.contains('burned') ||
      blob.contains('هاردساب') ||
      blob.contains('هارد ساب') ||
      RegExp(r'(^|[^a-z])hdts([^a-z]|$)').hasMatch(blob) ||
      blob.contains('hdcam');
  if (explicit) return true;
  final claimed = blob.contains('چسبیده') || blob.contains('زیرنویس') || blob.contains('سافت');
  return claimed && !sushiHasPlayableSub(subStreams);
}

bool sushiHasPlayableSub(List<SubStreamModel>? subStreams) {
  if (subStreams == null || subStreams.isEmpty) return false;
  return subStreams.any(sushiSubtitleTrackIsPlayable);
}

/// Resolves subtitle index when Fladder remembered Off / null but the server
/// (or preferred account-lang → en track) wants subtitles on.
///
/// Hardsub sources default to Off: enabling soft subs on top of burn-in
/// stacks a second identical subtitle on Android ExoPlayer.
int? sushiResolveSubtitleStreamIndex({
  required int? selectedIndex,
  required int? serverDefaultIndex,
  required List<SubStreamModel>? subStreams,
  String? mediaSourceName,
}) {
  final want = sushiAccountPlaybackPref.subtitleLangOrFa;
  bool isWantedTrack(int? index) {
    if (index == null || index == -1) return false;
    final track = subStreams?.firstWhereOrNull((s) => s.index == index);
    if (track == null) return false;
    return sushiSubtitleLangMatches(track.language, want) ||
        sushiSubtitleLangMatches(track.displayTitle, want) ||
        sushiSubtitleLangMatches(track.name, want);
  }

  final preferredIndex = sushiPreferredLangStreamIndex(subStreams, want);

  final selectedOn = selectedIndex != null &&
      selectedIndex != -1 &&
      subStreams?.any((s) => s.index == selectedIndex) == true;
  if (selectedOn) {
    // Preferred soft track exists but the current pick isn't it — prefer account lang.
    if (preferredIndex != null && !isWantedTrack(selectedIndex)) {
      return preferredIndex;
    }
    return selectedIndex;
  }

  if (sushiMediaSourceLooksHardSub(mediaSourceName, subStreams: subStreams)) {
    return -1;
  }

  // Server default Off — still prefer an available preferred soft track over staying off.
  if (serverDefaultIndex == -1) {
    return preferredIndex ?? -1;
  }

  if (serverDefaultIndex != null &&
      serverDefaultIndex != -1 &&
      subStreams?.any((s) => s.index == serverDefaultIndex) == true) {
    if (preferredIndex != null && !isWantedTrack(serverDefaultIndex)) {
      return preferredIndex;
    }
    return serverDefaultIndex;
  }

  return preferredIndex ?? sushiPreferredSubtitleStreamIndex(subStreams) ?? selectedIndex;
}

/// Muxed/external tracks have a codec and/or URL. Sushi `sub_langs` catalog
/// codes are empty-codec stubs — they are not a playable Farsi softsub.
bool sushiSubtitleTrackIsPlayable(SubStreamModel s) {
  if (s.index == -1) return false;
  final url = s.url?.trim() ?? '';
  if (url.isNotEmpty) return true;
  return s.codec.trim().isNotEmpty;
}

/// True when the container already has a playable Persian (Farsi) soft subtitle.
bool sushiHasPersianSoftSub(List<SubStreamModel>? subStreams) {
  if (subStreams == null || subStreams.isEmpty) return false;
  return subStreams.any((s) =>
      sushiSubtitleTrackIsPlayable(s) &&
      (SushiPersianLanguage.isPersianLanguage(s.language) ||
          SushiPersianLanguage.isPersianLanguage(s.displayTitle)));
}

/// What to apply at playback start. A previous title's AI / Automatic pick must not carry
/// over. A manual pick stored for this series (every episode) or this movie does.
enum SushiStartSubtitle { persianSoft, sniffEmbedded, automaticOnline, aiTranslate, off }

/// Manual subtitle choice for one series (shared by its episodes) or one movie.
enum SushiTitleSubtitleKind { off, track, automatic, ai }

class SushiTitleSubtitleMemory {
  const SushiTitleSubtitleMemory({required this.kind, this.language, this.label});

  final SushiTitleSubtitleKind kind;
  final String? language;
  final String? label;
}

/// Replay a stored manual pick. A track pick selects the same language (or the same
/// label) on the new file. No match stays Off — it does not fall through to the account plan.
SushiStartSubtitlePlan sushiPlanFromTitleSubtitleMemory({
  required SushiTitleSubtitleMemory memory,
  required List<SubStreamModel>? subStreams,
}) {
  switch (memory.kind) {
    case SushiTitleSubtitleKind.off:
      return const SushiStartSubtitlePlan(choice: SushiStartSubtitle.off, index: -1);
    case SushiTitleSubtitleKind.automatic:
      return const SushiStartSubtitlePlan(choice: SushiStartSubtitle.automaticOnline, index: -1);
    case SushiTitleSubtitleKind.ai:
      return const SushiStartSubtitlePlan(choice: SushiStartSubtitle.aiTranslate, index: -1);
    case SushiTitleSubtitleKind.track:
      final lang = memory.language?.trim() ?? '';
      var index = lang.isEmpty ? null : sushiPreferredLangStreamIndex(subStreams, lang);
      final label = memory.label?.trim().toLowerCase() ?? '';
      if (index == null && label.isNotEmpty) {
        index = subStreams?.where((s) => s.index != -1).firstWhereOrNull((s) {
          return s.displayTitle.trim().toLowerCase() == label || s.name.trim().toLowerCase() == label;
        })?.index;
      }
      return SushiStartSubtitlePlan(
        choice: index == null ? SushiStartSubtitle.off : SushiStartSubtitle.persianSoft,
        index: index ?? -1,
      );
  }
}

/// What to select at playback start, and which follow-up to run.
class SushiStartSubtitlePlan {
  const SushiStartSubtitlePlan({required this.choice, required this.index});

  final SushiStartSubtitle choice;

  /// Track index to select. -1 leaves subtitles off.
  final int index;
}

/// Preferred soft-lang label wins. `en` / empty / und gets a text sniff before online.
/// Anything else goes online. ([SushiStartSubtitle.persianSoft] = preferred soft match.)
SushiStartSubtitlePlan sushiPlanStartSubtitle({
  required List<SubStreamModel>? subStreams,
  String? mediaSourceName,
  bool isIranian = false,
  SushiAccountPlaybackPref? account,
}) {
  final pref = account ?? sushiAccountPlaybackPref;
  final hardSub = sushiMediaSourceLooksHardSub(mediaSourceName, subStreams: subStreams);
  final want = pref.subtitleLangOrFa;
  final preferredIndex = sushiPreferredLangStreamIndex(subStreams, want);
  final sniffIndex = sushiScriptSniffSubtitleIndex(subStreams, preferredLang: want);
  final choice = sushiStartSubtitleChoice(
    hardSub: hardSub,
    hasPersianSoft: preferredIndex != null,
    needsScriptSniff: sniffIndex != null,
    isIranian: isIranian,
    account: pref,
  );
  final index = switch (choice) {
    SushiStartSubtitle.persianSoft => preferredIndex ?? -1,
    SushiStartSubtitle.sniffEmbedded => sniffIndex ?? -1,
    SushiStartSubtitle.automaticOnline || SushiStartSubtitle.aiTranslate || SushiStartSubtitle.off => -1,
  };
  return SushiStartSubtitlePlan(choice: choice, index: index);
}

/// English, empty, or undetermined container tags. A real `fa` label is not sniffed.
bool sushiSubtitleLanguageNeedsScriptSniff(String? language) {
  if (SushiPersianLanguage.isPersianLanguage(language)) return false;
  final lang = (language ?? '').trim().toLowerCase();
  if (lang.isEmpty || lang == 'und' || lang == 'unknown' || lang == 'mul') return true;
  return sushiIsEnglishLanguage(language);
}

/// First muxed track whose label is English or unknown. Null when preferred soft lang exists.
int? sushiScriptSniffSubtitleIndex(
  List<SubStreamModel>? subStreams, {
  String? preferredLang,
}) {
  if (subStreams == null || subStreams.isEmpty) return null;
  final want = preferredLang ?? sushiAccountPlaybackPref.subtitleLangOrFa;
  if (sushiPreferredLangStreamIndex(subStreams, want) != null) return null;
  final track = subStreams.where((s) => s.index != -1).firstWhereOrNull(
        (s) => sushiSubtitleLanguageNeedsScriptSniff(s.language),
      );
  return track?.index;
}

/// Ordered start pipeline for a non-hard-sub item. Hard-sub is always empty (Off) —
/// burn-in must not get Automatic / AI / muxed Farsi stacked on top, including English-audio
/// prints (doc 15 §7: Persian-scene hardsub of an English movie already has Farsi on screen).
enum SushiStartSubtitleStep { automaticOnline, aiTranslate, persianSoft }

/// True when a track's language/title codes read as English ('en', 'eng', 'en-*', or a title
/// that says so). Same rule [sushiPreferredSubtitleStreamIndex] uses to spot an English track.
bool sushiIsEnglishLanguage(String? language) {
  final lang = (language ?? '').trim().toLowerCase();
  return lang == 'en' || lang == 'eng' || lang.startsWith('en-');
}

/// `fa` label is the whole chain (select that track, stop). Otherwise Automatic, then AI.
/// Hard-sub skips the chain (Off). English audio does not reopen it.
List<SushiStartSubtitleStep> sushiStartSubtitleSteps({
  required bool hardSub,
  required bool hasPersianSoft,
  required bool aiSet,
}) {
  if (hardSub) return const [];
  if (hasPersianSoft) return const [SushiStartSubtitleStep.persianSoft];
  return [
    SushiStartSubtitleStep.automaticOnline,
    if (aiSet) SushiStartSubtitleStep.aiTranslate,
  ];
}

/// `fa` label selects that track and stops. English or unknown labels sniff cue text first.
/// Hardsub stays Off. English audio does not change that (doc 15 §7).
///
/// Iranian content is skipped entirely: it's already Persian, so auto subtitle search has
/// nothing useful to look for.
SushiStartSubtitle sushiStartSubtitleChoice({
  required bool hardSub,
  required bool hasPersianSoft,
  bool needsScriptSniff = false,
  bool subtitleOff = false,
  bool isEnglishAudio = false,
  bool isIranian = false,
  SushiAccountPlaybackPref? account,
}) {
  final pref = account ?? sushiAccountPlaybackPref;
  if (pref.wantsSubtitlesOff) return SushiStartSubtitle.off;
  if (isIranian) return SushiStartSubtitle.off;
  if (hardSub) return SushiStartSubtitle.off;
  // Non-Persian + "with subtitles": skip muxed tracks and go straight to auto online.
  if (pref.wantsAutoOnlineSubtitles) return SushiStartSubtitle.automaticOnline;
  if (hasPersianSoft) return SushiStartSubtitle.persianSoft;
  if (needsScriptSniff) return SushiStartSubtitle.sniffEmbedded;
  return SushiStartSubtitle.automaticOnline;
}

/// First playable Persian (Farsi) track, or null when none is available.
int? sushiPreferredPersianStreamIndex(List<SubStreamModel>? subStreams) {
  return sushiPreferredLangStreamIndex(subStreams, 'fa');
}

/// First playable track matching [preferredLang] (ISO 639-1 / aliases), or null.
int? sushiPreferredLangStreamIndex(List<SubStreamModel>? subStreams, String preferredLang) {
  if (subStreams == null || subStreams.isEmpty) return null;
  final want = preferredLang.trim().toLowerCase();
  if (want.isEmpty) return sushiPreferredPersianStreamIndex(subStreams);
  final real = subStreams.where((s) => s.index != -1).toList();
  if (real.isEmpty) return null;

  if (sushiSubtitleLangIsPersian(want)) {
    final persian = real.firstWhereOrNull(
      (s) =>
          SushiPersianLanguage.isPersianLanguage(s.language) ||
          SushiPersianLanguage.isPersianLanguage(s.displayTitle) ||
          SushiPersianLanguage.isPersianLanguage(s.name),
    );
    return persian?.index;
  }

  final match = real.firstWhereOrNull(
    (s) =>
        sushiSubtitleLangMatches(s.language, want) ||
        sushiSubtitleLangMatches(s.displayTitle, want) ||
        sushiSubtitleLangMatches(s.name, want),
  );
  return match?.index;
}

/// Account preferred lang first, then English, else first real track.
int? sushiPreferredSubtitleStreamIndex(List<SubStreamModel>? subStreams) {
  if (subStreams == null || subStreams.isEmpty) return null;
  final real = subStreams.where((s) => s.index != -1).toList();
  if (real.isEmpty) return null;

  final want = sushiAccountPlaybackPref.subtitleLangOrFa;
  final preferred = sushiPreferredLangStreamIndex(subStreams, want);
  if (preferred != null) return preferred;

  final english = real.firstWhereOrNull((s) {
    final title = s.displayTitle.trim().toLowerCase();
    return sushiIsEnglishLanguage(s.language) || title.contains('english') || title == 'en';
  });
  if (english != null) return english.index;

  return real.first.index;
}

/// Rewrite one muxed track's label to Persian after a text sniff.
MediaStreamsModel? sushiRelabelSubtitleAsPersian(MediaStreamsModel? streams, int index) {
  if (streams == null || index < 0) return streams;
  final current = streams.currentVersionStream;
  if (current == null) return streams;
  final versions = [
    for (final version in streams.versionStreams)
      identical(version, current)
          ? VersionStreamModel(
              name: version.name,
              index: version.index,
              id: version.id,
              defaultAudioStreamIndex: version.defaultAudioStreamIndex,
              defaultSubStreamIndex: index,
              videoStreams: version.videoStreams,
              audioStreams: version.audioStreams,
              subStreams: [
                for (final sub in version.subStreams)
                  sub.index == index
                      ? sub.copyWith(language: 'fa', displayTitle: 'FA', name: 'FA', title: 'FA')
                      : sub,
              ],
              sizeBytes: version.sizeBytes,
            )
          : version,
  ];
  return streams.copyWith(defaultSubStreamIndex: index, versionStreams: versions);
}
