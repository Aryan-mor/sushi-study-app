import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_account_playback_pref.dart';
import 'package:fladder/sushi/sushi_media_variant.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

const _prefsKey = 'sushi_variant_pref_v1';
const _maxEntries = 300;

/// Per-title key for the locally remembered quality/delivery pick: `movie:<tmdbId>` for a
/// movie, `series:<tmdbId>` for a series or one of its episodes (so every episode of a show
/// shares the same pick), or null when the item's TMDB id can't be resolved.
String? sushiVariantPreferenceKeyFor(ItemBaseModel item) {
  if (item is EpisodeModel) {
    final tmdb = sushiTmdbIdFromItemId(item.parentId ?? '');
    return tmdb == null ? null : 'series:$tmdb';
  }
  if (item is SeriesModel) {
    final tmdb = sushiTmdbIdFromItemId(item.id);
    return tmdb == null ? null : 'series:$tmdb';
  }
  final tmdb = sushiTmdbIdFromItemId(item.id);
  return tmdb == null ? null : 'movie:$tmdb';
}

Future<SushiMediaVariantPreference?> sushiReadVariantPreference(String key) async {
  // Every pick-list build reads the per-title pick first; loading the account answer here means
  // the synchronous cold-start pick behind it (sushiPickColdVersionStreamIndex) can see it too.
  await sushiLoadAccountPlaybackPref();
  final all = await _readAll();
  final raw = all[key];
  if (raw == null) return null;
  final height = raw['h'] as int?;
  final deliveryRaw = raw['d'] as String?;
  return SushiMediaVariantPreference(
    qualityHeight: height,
    delivery: deliveryRaw == null ? null : SushiStreamDelivery.values.byName(deliveryRaw),
  );
}

Future<void> sushiWriteVariantPreference(String key, SushiMediaVariantPreference pref) async {
  final all = await _readAll();
  all[key] = {
    if (pref.qualityHeight != null) 'h': pref.qualityHeight,
    if (pref.delivery != null) 'd': pref.delivery!.name,
    'atMs': DateTime.now().millisecondsSinceEpoch,
  };
  await _writeAll(_evictOldest(all));
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
