import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/sushi/sushi_catalog_http.dart';
import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/sushi/providers/sushi_watchlist_dashboard.dart';
import 'package:fladder/providers/api_provider.dart';

part 'sushi_catalog_item_flags.g.dart';

class SushiCatalogItemFlagsState {
  const SushiCatalogItemFlagsState({
    this.favoriteIds = const {},
    this.playedIds = const {},
    this.watchlistIds = const {},
    this.followingIds = const {},
    this.loaded = false,
  });

  final Set<String> favoriteIds;
  final Set<String> playedIds;
  final Set<String> watchlistIds;
  final Set<String> followingIds;
  final bool loaded;

  static const empty = SushiCatalogItemFlagsState();

  bool isFavorite(String id) => favoriteIds.contains(id);
  bool isPlayed(String id) => playedIds.contains(id);
  bool isWatchlisted(String id) => watchlistIds.contains(id);
  bool isFollowing(String id) => followingIds.contains(id);

  SushiCatalogItemFlagsState copyWith({
    Set<String>? favoriteIds,
    Set<String>? playedIds,
    Set<String>? watchlistIds,
    Set<String>? followingIds,
    bool? loaded,
  }) {
    return SushiCatalogItemFlagsState(
      favoriteIds: favoriteIds ?? this.favoriteIds,
      playedIds: playedIds ?? this.playedIds,
      watchlistIds: watchlistIds ?? this.watchlistIds,
      followingIds: followingIds ?? this.followingIds,
      loaded: loaded ?? this.loaded,
    );
  }
}

Set<String> _idsFromJson(dynamic raw) {
  if (raw is! List) return {};
  return {
    for (final e in raw)
      if (e is String && e.isNotEmpty) e,
  };
}

const _playedPrefsKey = 'sushi_played_ids_v1';

Future<Set<String>> _readLocalPlayed() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_playedPrefsKey);
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return {};
    return {
      for (final e in decoded)
        if (e is String && e.isNotEmpty) e,
    };
  } catch (_) {
    return {};
  }
}

Future<void> _writeLocalPlayed(Set<String> ids) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_playedPrefsKey, jsonEncode(ids.toList()));
}

@Riverpod(keepAlive: true)
class SushiCatalogItemFlags extends _$SushiCatalogItemFlags {
  @override
  SushiCatalogItemFlagsState build() {
    Future.microtask(_mergeLocalPlayed);
    return SushiCatalogItemFlagsState.empty;
  }

  Future<void> _mergeLocalPlayed() async {
    final local = await _readLocalPlayed();
    if (local.isEmpty) return;
    state = state.copyWith(playedIds: {...state.playedIds, ...local});
  }

  Future<void> load() async {
    if (!SushiEnv.isEnabled) {
      await _mergeLocalPlayed();
      return;
    }
    final baseUrl = ref.read(serverUrlProvider);
    if (baseUrl == null || baseUrl.isEmpty) {
      await _mergeLocalPlayed();
      return;
    }
    final headers = sushiCatalogApiHeaders(ref);
    if (headers.isEmpty) {
      await _mergeLocalPlayed();
      return;
    }

    final uri = Uri.parse('$baseUrl/me/item-flags');
    try {
      final response = await http.get(uri, headers: headers);
      final local = await _readLocalPlayed();
      if (response.statusCode != 200) {
        developer.log(
          'GET ${uri.path} failed status=${response.statusCode}',
          name: 'SushiCatalogItemFlags',
        );
        if (local.isNotEmpty) {
          state = state.copyWith(playedIds: {...state.playedIds, ...local});
        }
        return;
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return;
      final serverPlayed = _idsFromJson(body['playedIds']);
      // Client-owned episode ids live in memory/prefs. GET must not wipe them.
      final playedIds = {...serverPlayed, ...state.playedIds, ...local};
      state = SushiCatalogItemFlagsState(
        favoriteIds: _idsFromJson(body['favoriteIds']),
        playedIds: playedIds,
        watchlistIds: _idsFromJson(body['watchlistIds']),
        followingIds: _idsFromJson(body['followingIds']),
        loaded: true,
      );
    } catch (e, st) {
      developer.log('GET /me/item-flags failed', name: 'SushiCatalogItemFlags', error: e, stackTrace: st);
      await _mergeLocalPlayed();
    }
  }

  void setFavorite(String id, bool value) {
    if (id.isEmpty) return;
    final next = {...state.favoriteIds};
    if (value) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(favoriteIds: next);
  }

  Future<void> setPlayed(String id, bool value) async {
    if (id.isEmpty) return;
    await setPlayedMany([id], value);
  }

  Future<void> setPlayedMany(Iterable<String> ids, bool value) async {
    final next = {...state.playedIds};
    var changed = false;
    for (final id in ids) {
      if (id.isEmpty) continue;
      if (value) {
        changed = next.add(id) || changed;
      } else {
        changed = next.remove(id) || changed;
      }
    }
    if (!changed) return;
    state = state.copyWith(playedIds: next);
    await _writeLocalPlayed(next);
  }

  /// Cross-device sync delta (docs/11 §6.1). [ids] are `sushi_ep_<n>`.
  Future<void> applyWatchedIds(Map<String, bool> marks) async {
    if (marks.isEmpty) return;
    final next = {...state.playedIds};
    var changed = false;
    for (final entry in marks.entries) {
      if (entry.key.isEmpty) continue;
      if (entry.value) {
        changed = next.add(entry.key) || changed;
      } else {
        changed = next.remove(entry.key) || changed;
      }
    }
    if (!changed) return;
    state = state.copyWith(playedIds: next);
    await _writeLocalPlayed(next);
  }

  void setWatchlisted(String id, bool value) {
    if (id.isEmpty) return;
    final next = {...state.watchlistIds};
    if (value) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(watchlistIds: next);
  }

  void setFollowing(String id, bool value) {
    if (id.isEmpty) return;
    final next = {...state.followingIds};
    if (value) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(followingIds: next);
  }

  Future<bool> toggleFollowing(String catalogId) async {
    if (!SushiEnv.isEnabled || catalogId.isEmpty) return false;
    final baseUrl = ref.read(serverUrlProvider);
    if (baseUrl == null || baseUrl.isEmpty) return false;
    final headers = sushiCatalogApiHeaders(ref);
    if (headers.isEmpty) return false;

    final next = !state.isFollowing(catalogId);
    final uri = Uri.parse('$baseUrl/me/follows/$catalogId');
    final response = next ? await http.put(uri, headers: headers) : await http.delete(uri, headers: headers);
    if (response.statusCode != 200) {
      developer.log(
        '${next ? 'PUT' : 'DELETE'} ${uri.path} failed status=${response.statusCode}',
        name: 'SushiCatalogItemFlags',
      );
      return false;
    }
    setFollowing(catalogId, next);
    return true;
  }

  Future<bool> toggleWatchlisted(String catalogId) async {
    if (!SushiEnv.isEnabled || catalogId.isEmpty) return false;
    final baseUrl = ref.read(serverUrlProvider);
    if (baseUrl == null || baseUrl.isEmpty) return false;
    final headers = sushiCatalogApiHeaders(ref);
    if (headers.isEmpty) return false;

    final next = !state.isWatchlisted(catalogId);
    final uri = Uri.parse('$baseUrl/me/watchlist/$catalogId');
    final response = next ? await http.put(uri, headers: headers) : await http.delete(uri, headers: headers);
    if (response.statusCode != 200) {
      developer.log(
        '${next ? 'PUT' : 'DELETE'} ${uri.path} failed status=${response.statusCode}',
        name: 'SushiCatalogItemFlags',
      );
      return false;
    }
    setWatchlisted(catalogId, next);
    sushiResetWatchlistHomeFeedRef(ref);
    ref.invalidate(sushiWatchlistDashboardProvider);
    return true;
  }

  void clear() => state = SushiCatalogItemFlagsState.empty;
}
