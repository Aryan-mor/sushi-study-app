import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/sushi/sushi_account_playback_pref.dart';
import 'package:fladder/sushi/sushi_playback_prefetch.dart';
import 'package:fladder/sushi/sushi_share.dart';
import 'package:fladder/sushi/sushi_play_warmup.dart';
import 'package:fladder/sushi/sushi_variant_preference_store.dart';

/// Delivery / track flavor for a file variant (soft sub, dubbed, etc.).
enum SushiStreamDelivery {
  softSub,
  dubbed,
  hardSub,
  original,
  unknown,
}

/// User's last explicit version pick for one title (movie or series), persisted locally
/// per-title in [sushiVariantPreferenceKeyFor] — see `sushi_variant_preference_store.dart`.
class SushiMediaVariantPreference {
  const SushiMediaVariantPreference({
    this.qualityHeight,
    this.delivery,
  });

  /// Normalized height tier: 2160, 1080, 720, …
  final int? qualityHeight;
  final SushiStreamDelivery? delivery;

  bool get hasUserChoice => qualityHeight != null || delivery != null;

  static const unset = SushiMediaVariantPreference();

  SushiMediaVariantPreference copyWith({
    int? qualityHeight,
    SushiStreamDelivery? delivery,
    bool clearQuality = false,
    bool clearDelivery = false,
  }) {
    return SushiMediaVariantPreference(
      qualityHeight: clearQuality ? null : (qualityHeight ?? this.qualityHeight),
      delivery: clearDelivery ? null : (delivery ?? this.delivery),
    );
  }
}

class SushiVersionStreamMeta {
  const SushiVersionStreamMeta({
    required this.qualityHeight,
    required this.delivery,
  });

  final int? qualityHeight;
  final SushiStreamDelivery delivery;
}

const _defaultQualityTiers = [1080, 720, 576, 480, 360, 2160, 1440];

SushiVersionStreamMeta sushiClassifyVersionStream(VersionStreamModel stream) {
  final blob = '${stream.name} ${stream.detailedResolutionLabel}'.toLowerCase();
  final hasCatalogSubs = stream.subStreams.any((s) => s.index != -1);
  final delivery = sushiClassifyDeliveryLabel(blob, hasCatalogSubs: hasCatalogSubs);
  final qualityHeight = _qualityHeightFromLabel(blob) ?? _qualityHeightFromVideo(stream);
  return SushiVersionStreamMeta(qualityHeight: qualityHeight, delivery: delivery);
}

/// Delivery from a release label (+ optional catalog sub_langs signal). Shared by the picker
/// and [sushiFilterFilesForSubtitlePref].
SushiStreamDelivery sushiClassifyDeliveryLabel(String label, {bool hasCatalogSubs = false}) {
  final blob = label.toLowerCase();
  // Dub label first: dubbed files often still list soft-sub tracks in sub_langs, and treating
  // those as softSub made account "prefer dub" pick the wrong version.
  if (RegExp(r'(?:^|[^a-z0-9])(?:dub(?:bed)?|duble)(?:$|[^a-z0-9])').hasMatch(blob) ||
      blob.contains('دوبله') ||
      blob.contains('🎙')) {
    return SushiStreamDelivery.dubbed;
  }
  // Real soft-sub tracks (catalog sub_langs → stub subStreams) beat a hardsub-looking label
  // (e.g. چسبیده on a file that actually muxed fa subs).
  if (hasCatalogSubs ||
      RegExp(r'soft[\s_-]*sub').hasMatch(blob) ||
      blob.contains('softsub') ||
      blob.contains('سافت') ||
      RegExp(r'soft\s+sub').hasMatch(blob)) {
    return SushiStreamDelivery.softSub;
  }
  if (RegExp(r'hard[\s_-]*sub').hasMatch(blob) ||
      blob.contains('hardsub') ||
      blob.contains('هاردساب') ||
      blob.contains('هارد ساب') ||
      blob.contains('burned') ||
      RegExp(r'(^|[^a-z])hdts([^a-z]|$)').hasMatch(blob) ||
      blob.contains('hdcam') ||
      RegExp(r'hard\s+sub').hasMatch(blob) ||
      blob.contains('چسبیده')) {
    return SushiStreamDelivery.hardSub;
  }
  if (blob.contains('original')) {
    return SushiStreamDelivery.original;
  }
  return SushiStreamDelivery.original;
}

int? _qualityHeightFromLabel(String blob) {
  // `\b` doesn't break between `_`/`.` and a digit, so it silently misses resolution
  // tokens in underscore/dot-delimited release filenames (`..._1080p_...`). `blob` is
  // already lower-cased by the caller.
  final match = RegExp(r'(?:^|[^a-z0-9])(2160|1440|1080|720|576|480|360)p?(?:$|[^a-z0-9])').firstMatch(blob);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

int? _qualityHeightFromVideo(VersionStreamModel stream) {
  final height = stream.videoStreams.firstOrNull?.height;
  if (height == null || height <= 0) return null;
  return sushiNormalizeQualityHeight(height);
}

int sushiNormalizeQualityHeight(int height) {
  if (height >= 1900) return 2160;
  if (height >= 1200) return 1440;
  if (height >= 900) return 1080;
  if (height >= 600) return 720;
  if (height >= 510) return 576;
  if (height >= 420) return 480;
  if (height >= 330) return 360;
  return height;
}

/// Pick a [versionStreams] index using saved preference or cold-start defaults. [account] is the
/// user's onboarding answer; null reads the one the last sync stored.
int sushiPickVersionStreamIndex(
  List<VersionStreamModel> streams,
  SushiMediaVariantPreference preference, {
  SushiAccountPlaybackPref? account,
}) {
  if (streams.isEmpty) return 0;
  if (streams.length == 1) return streams.first.index;

  final classified = streams
      .map((stream) => (stream: stream, meta: sushiClassifyVersionStream(stream)))
      .toList();

  if (preference.hasUserChoice) {
    final idx = _findIndexForPreference(classified, preference);
    if (idx != null) return idx;
  }
  return _pickColdDefault(classified, account ?? sushiAccountPlaybackPref);
}

/// The version to open a title on when the user never picked one for it: the account answer
/// ("subtitles over dubbing", max quality) ranks the list; with no answer, the historic rule.
int sushiPickColdVersionStreamIndex(List<VersionStreamModel> streams, {SushiAccountPlaybackPref? account}) {
  if (streams.isEmpty) return 0;
  if (streams.length == 1) return streams.first.index;
  final classified = streams.map((stream) => (stream: stream, meta: sushiClassifyVersionStream(stream))).toList();
  return _pickColdDefault(classified, account ?? sushiAccountPlaybackPref);
}

/// Locates a [streams] index that reasonably matches [preference], or null when [streams]
/// has nothing to match against (fewer than 2 versions, or no preference set). Unlike
/// [sushiPickVersionStreamIndex] this never falls back to a cold-start default — callers use
/// that to distinguish "the local preference actually matched something" from "there was
/// nothing to go on," so they can fall back to a different signal (e.g. the server's last
/// played file) before finally cold-starting.
int? sushiFindVersionStreamIndexForPreference(
  List<VersionStreamModel> streams,
  SushiMediaVariantPreference? preference,
) {
  if (preference == null || !preference.hasUserChoice) return null;
  if (streams.length <= 1) return null;
  final classified = streams.map((stream) => (stream: stream, meta: sushiClassifyVersionStream(stream))).toList();
  return _findIndexForPreference(classified, preference);
}

List<({VersionStreamModel stream, SushiVersionStreamMeta meta})> _pinnedOrAll(
  List<({VersionStreamModel stream, SushiVersionStreamMeta meta})> classified,
) {
  final pinned = [
    for (final entry in classified)
      if (entry.stream.displayName.trim().isNotEmpty) entry,
  ];
  return pinned.isEmpty ? classified : pinned;
}

int _pickColdDefault(
  List<({VersionStreamModel stream, SushiVersionStreamMeta meta})> classified,
  SushiAccountPlaybackPref account,
) {
  classified = _pinnedOrAll(classified);
  if (!account.isUnset) {
    final effective = SushiAccountPlaybackPref(
      audio: account.audioForVersionPick,
      maxHeight: account.maxHeight,
      subtitleLang: account.subtitleLang,
      subs: account.subs,
    );
    return _pickForAccount(classified, effective);
  }
  for (final tier in const [1080, 720]) {
    final soft = classified.firstWhereOrNull(
      (e) => e.meta.qualityHeight == tier && e.meta.delivery == SushiStreamDelivery.softSub,
    );
    if (soft != null) return soft.stream.index;

    final any = classified.firstWhereOrNull((e) => e.meta.qualityHeight == tier);
    if (any != null) return any.stream.index;
  }

  for (final tier in _defaultQualityTiers) {
    if (tier == 1080 || tier == 720) continue;
    final match = classified.firstWhereOrNull((e) => e.meta.qualityHeight == tier);
    if (match != null) return match.stream.index;
  }

  return classified.first.stream.index;
}

/// Delivery first -- someone who asked for subtitles gets a subtitled 720p before a dubbed 1080p --
/// then the height closest to (and not above) their max, 1080 when they never said.
int _pickForAccount(
  List<({VersionStreamModel stream, SushiVersionStreamMeta meta})> classified,
  SushiAccountPlaybackPref account,
) {
  classified = _pinnedOrAll(classified);
  final target = account.maxHeight > 0 ? account.maxHeight : 1080;
  // Persian + "with subtitles" (and not a dub request): burned-in first, then a
  // Persian soft track. "Without" pushes hardsub to the bottom so burn-in is not
  // the default. Unset keeps the historic soft-sub-first order.
  final persianWithSubs = account.wantsSubtitlesOn &&
      account.wantsPersianSubtitles &&
      account.audio != SushiAudioPref.dub;
  int deliveryRank(SushiStreamDelivery d) {
    if (persianWithSubs) {
      return switch (d) {
        SushiStreamDelivery.hardSub => 0,
        SushiStreamDelivery.softSub => 1,
        SushiStreamDelivery.dubbed => 3,
        _ => 2,
      };
    }
    final rank = switch (account.audio) {
      SushiAudioPref.original => switch (d) {
          SushiStreamDelivery.softSub => 0,
          SushiStreamDelivery.hardSub => 1,
          SushiStreamDelivery.dubbed => 3,
          _ => 2,
        },
      SushiAudioPref.dub => switch (d) {
          SushiStreamDelivery.dubbed => 0,
          SushiStreamDelivery.softSub => 1,
          SushiStreamDelivery.hardSub => 2,
          _ => 3,
        },
      SushiAudioPref.unset => d == SushiStreamDelivery.softSub ? 0 : 1,
    };
    if (account.wantsSubtitlesOff && d == SushiStreamDelivery.hardSub) return rank + 10;
    return rank;
  }
  int qualityRank(int? h) {
    if (h == null) return 1 << 20;
    return h <= target ? target - h : (1 << 16) + (h - target);
  }

  // Prefer a file that already has a soft track for the account subtitle lang
  // (defaultSub ≥ 0 after sushiBuildMediaStreams filters). Softsub with only
  // the wrong lang stays selectable but ranks lower — playback goes online/AI.
  int subMatchRank(VersionStreamModel s) =>
      (s.defaultSubStreamIndex != null && s.defaultSubStreamIndex! >= 0) ? 0 : 1;

  final ranked = [...classified]..sort((a, b) {
      final byDelivery = deliveryRank(a.meta.delivery).compareTo(deliveryRank(b.meta.delivery));
      if (byDelivery != 0) return byDelivery;
      final byQuality = qualityRank(a.meta.qualityHeight).compareTo(qualityRank(b.meta.qualityHeight));
      if (byQuality != 0) return byQuality;
      final bySub = subMatchRank(a.stream).compareTo(subMatchRank(b.stream));
      if (bySub != 0) return bySub;
      return a.stream.index.compareTo(b.stream.index);
    });
  return ranked.first.stream.index;
}

int? _findIndexForPreference(
  List<({VersionStreamModel stream, SushiVersionStreamMeta meta})> classified,
  SushiMediaVariantPreference preference,
) {
  final tiers = _qualityTiersToTry(preference.qualityHeight);
  final preferredDelivery = preference.delivery;

  if (preference.qualityHeight != null) {
    final tier = preference.qualityHeight!;
    for (final delivery in _deliveryFallbacks(preferredDelivery, includeOriginal: false)) {
      final match = classified.firstWhereOrNull(
        (e) => e.meta.qualityHeight == tier && e.meta.delivery == delivery,
      );
      if (match != null) return match.stream.index;
    }
    if (preferredDelivery == null) {
      final anyAtTier = classified.firstWhereOrNull((e) => e.meta.qualityHeight == tier);
      if (anyAtTier != null) return anyAtTier.stream.index;
    }
  }

  for (final tier in tiers) {
    if (tier == preference.qualityHeight) continue;
    if (preferredDelivery != null) {
      final dubbedMatch = classified.firstWhereOrNull(
        (e) => e.meta.qualityHeight == tier && e.meta.delivery == preferredDelivery,
      );
      if (dubbedMatch != null) return dubbedMatch.stream.index;
    }
    for (final delivery in _deliveryFallbacks(preferredDelivery)) {
      final match = classified.firstWhereOrNull(
        (e) => e.meta.qualityHeight == tier && e.meta.delivery == delivery,
      );
      if (match != null) return match.stream.index;
    }
    final anyAtTier = classified.firstWhereOrNull((e) => e.meta.qualityHeight == tier);
    if (anyAtTier != null) return anyAtTier.stream.index;
  }

  for (final delivery in _deliveryFallbacks(preferredDelivery)) {
    final match = classified.firstWhereOrNull((e) => e.meta.delivery == delivery);
    if (match != null) return match.stream.index;
  }

  return null;
}

List<int> _qualityTiersToTry(int? preferred) {
  if (preferred == null) return _defaultQualityTiers;
  final rest = _defaultQualityTiers.where((t) => t != preferred).toList();
  return [preferred, ...rest];
}

List<SushiStreamDelivery> _deliveryFallbacks(
  SushiStreamDelivery? preferred, {
  bool includeOriginal = true,
}) {
  const core = [
    SushiStreamDelivery.softSub,
    SushiStreamDelivery.dubbed,
    SushiStreamDelivery.hardSub,
  ];
  final base = preferred == null
      ? core
      : [preferred, ...core.where((d) => d != preferred)];
  if (!includeOriginal) return base;
  return [...base, SushiStreamDelivery.original, SushiStreamDelivery.unknown];
}

/// Applies a locally remembered per-title [preference] to already-built [streams] (used for
/// the series episode-list rail, where each episode's streams were built without a
/// `preferredFileId`/`localPreference` at fetch time). The main movie/episode load paths
/// instead pass the preference straight into [sushiBuildMediaStreams].
MediaStreamsModel sushiApplyVersionStreamPreference(
  MediaStreamsModel streams,
  SushiMediaVariantPreference? preference,
) {
  if (streams.versionStreams.length <= 1) {
    return streams;
  }
  final idx = sushiPickVersionStreamIndex(streams.versionStreams, preference ?? SushiMediaVariantPreference.unset);
  if (idx == (streams.versionStreamIndex ?? 0)) return streams;
  return streams.copyWith(versionStreamIndex: idx);
}

/// Persists [streams]'s currently selected version as the new per-title preference for
/// [owner] (a movie, or an episode — remembered against its series so every episode shares
/// the pick). Fire-and-forget; the in-memory model already reflects the choice immediately.
void sushiRememberMediaStreamsSelection(ItemBaseModel owner, MediaStreamsModel streams) {
  final current = streams.currentVersionStream;
  if (current == null) return;
  final key = sushiVariantPreferenceKeyFor(owner);
  if (key == null) return;
  final meta = sushiClassifyVersionStream(current);
  final pref = SushiMediaVariantPreference(
    qualityHeight: meta.qualityHeight,
    delivery: meta.delivery == SushiStreamDelivery.unknown ? null : meta.delivery,
  );
  unawaited(sushiWriteVariantPreference(key, pref));
}

MediaStreamsModel sushiOnUserMediaStreamsChanged(
  WidgetRef ref,
  MediaStreamsModel changed,
  ItemBaseModel owner,
) {
  sushiRememberMediaStreamsSelection(owner, changed);
  sushiPlayWarmup.scheduleFromStreams(changed);
  final itemId = owner.id;
  if (itemId.isNotEmpty) {
    final msId = changed.currentVersionStream?.id;
    if (msId != null && msId.isNotEmpty) {
      SushiPlaybackPrefetch.scheduleForItem(ref.read, itemId, mediaSourceId: msId);
    }
  }
  return changed;
}

EpisodeModel? sushiPrepareEpisodeMediaStreams(
  EpisodeModel? episode,
  Ref ref, {
  SushiMediaVariantPreference? localPreference,
}) {
  if (episode == null) return episode;
  var item = sushiApplyShareMediaSourceToEpisode(episode, ref) ?? episode;
  final streams = sushiApplyVersionStreamPreference(item.mediaStreams, localPreference);
  if (streams == item.mediaStreams) return item;
  return item.copyWith(mediaStreams: streams);
}

List<EpisodeModel> sushiPrepareEpisodeListMediaStreams(
  Ref ref,
  List<EpisodeModel> episodes, {
  SushiMediaVariantPreference? localPreference,
}) {
  if (episodes.isEmpty) return episodes;
  return episodes
      .map((episode) =>
          sushiPrepareEpisodeMediaStreams(episode, ref, localPreference: localPreference) ?? episode)
      .toList();
}
