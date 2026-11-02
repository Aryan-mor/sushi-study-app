import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/sushi/sushi_playback_subtitle.dart';
import 'package:fladder/sushi/sushi_variant_preference_store.dart';

const _prefsKey = 'sushi_title_subtitle_v1';
const _maxEntries = 300;

int _manualChoiceGen = 0;
Future<void> _writeChain = Future<void>.value();

/// Call when the user picks again. A slower Automatic / AI job from the previous pick
/// must not overwrite this one.
int sushiBeginManualSubtitleChoice() => ++_manualChoiceGen;

/// Last manual subtitle pick for this series (every episode shares it) or this movie.
/// Null when the user has not overridden the account plan for this title.
Future<SushiTitleSubtitleMemory?> sushiReadTitleSubtitle(ItemBaseModel item) async {
  final key = sushiVariantPreferenceKeyFor(item);
  if (key == null) return null;
  final raw = (await _readAll())[key];
  if (raw == null) return null;
  final kind = _kindFromWire(raw['k'] as String?);
  if (kind == null) return null;
  return SushiTitleSubtitleMemory(
    kind: kind,
    language: raw['lang'] as String?,
    label: raw['label'] as String?,
  );
}

Future<void> sushiWriteTitleSubtitle(
  ItemBaseModel item,
  SushiTitleSubtitleMemory memory, {
  int? choiceGen,
}) {
  final done = _writeChain.then((_) => _writeTitleSubtitle(item, memory, choiceGen: choiceGen));
  _writeChain = done.catchError((_) {});
  return done;
}

Future<void> _writeTitleSubtitle(
  ItemBaseModel item,
  SushiTitleSubtitleMemory memory, {
  int? choiceGen,
}) async {
  if (choiceGen != null && choiceGen != _manualChoiceGen) return;
  final key = sushiVariantPreferenceKeyFor(item);
  if (key == null) return;
  final all = await _readAll();
  if (choiceGen != null && choiceGen != _manualChoiceGen) return;
  all[key] = {
    'k': _kindToWire(memory.kind),
    if (memory.language != null && memory.language!.trim().isNotEmpty) 'lang': memory.language!.trim(),
    if (memory.label != null && memory.label!.trim().isNotEmpty) 'label': memory.label!.trim(),
    'atMs': DateTime.now().millisecondsSinceEpoch,
  };
  await _writeAll(_evictOldest(all));
}

/// Off, or the muxed track the user tapped (matched later by language, then label).
Future<void> sushiRememberManualSubtitleTrack(ItemBaseModel item, SubStreamModel? track) {
  final choiceGen = sushiBeginManualSubtitleChoice();
  if (track == null || track.index < 0) {
    return sushiWriteTitleSubtitle(
      item,
      const SushiTitleSubtitleMemory(kind: SushiTitleSubtitleKind.off),
      choiceGen: choiceGen,
    );
  }
  final lang = track.language.trim();
  final label = track.displayTitle.trim().isNotEmpty ? track.displayTitle.trim() : track.name.trim();
  return sushiWriteTitleSubtitle(
    item,
    SushiTitleSubtitleMemory(
      kind: SushiTitleSubtitleKind.track,
      language: lang.isEmpty ? null : lang,
      label: label.isEmpty ? null : label,
    ),
    choiceGen: choiceGen,
  );
}

SushiTitleSubtitleKind? _kindFromWire(String? raw) {
  return switch (raw) {
    'off' => SushiTitleSubtitleKind.off,
    'track' => SushiTitleSubtitleKind.track,
    'auto' => SushiTitleSubtitleKind.automatic,
    'ai' => SushiTitleSubtitleKind.ai,
    _ => null,
  };
}

String _kindToWire(SushiTitleSubtitleKind kind) {
  return switch (kind) {
    SushiTitleSubtitleKind.off => 'off',
    SushiTitleSubtitleKind.track => 'track',
    SushiTitleSubtitleKind.automatic => 'auto',
    SushiTitleSubtitleKind.ai => 'ai',
  };
}

Map<String, Map<String, Object?>> _evictOldest(Map<String, Map<String, Object?>> all) {
  if (all.length <= _maxEntries) return all;
  final entries = all.entries.toList()
    ..sort((a, b) => ((a.value['atMs'] as int?) ?? 0).compareTo((b.value['atMs'] as int?) ?? 0));
  final dropKeys = entries.take(all.length - _maxEntries).map((e) => e.key).toSet();
  return Map.fromEntries(all.entries.where((e) => !dropKeys.contains(e.key)));
}

Future<Map<String, Map<String, Object?>>> _readAll() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_prefsKey);
  if (raw == null || raw.isEmpty) return {};
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((key, value) => MapEntry(key, Map<String, Object?>.from(value as Map)));
  } catch (_) {
    return {};
  }
}

Future<void> _writeAll(Map<String, Map<String, Object?>> all) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsKey, jsonEncode(all));
}
