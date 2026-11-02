import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-session set of item ids whose Sushi `/item` network refresh has completed at least once.
/// Until an id lands here the detail screen shows neither Play nor Request: the pre-fetch
/// placeholder card cannot tell "no file" from "not loaded yet", which is what made Request flash
/// before Play (ADR 0014).
final sushiTitleResolvedProvider =
    StateNotifierProvider<SushiTitleResolvedNotifier, Set<String>>(
  (ref) => SushiTitleResolvedNotifier(),
);

class SushiTitleResolvedNotifier extends StateNotifier<Set<String>> {
  SushiTitleResolvedNotifier() : super(const {});

  void markResolved(String? itemId) {
    if (itemId == null || itemId.isEmpty || state.contains(itemId)) return;
    state = {...state, itemId};
  }
}

/// True once this item's `/item` has resolved (or always, off Sushi).
bool sushiTitleResolved(WidgetRef ref, String? itemId, {required bool sushiEnabled}) =>
    !sushiEnabled || (itemId != null && ref.watch(sushiTitleResolvedProvider).contains(itemId));

/// `tmdbId:kind` keys the user has an open content request for (ADR 0014 §D2). Persisted so the
/// "Requested" button state survives a restart — the real "it's ready" signal is a main-bot
/// Telegram DM, and the server treats a re-request as a no-op anyway.
final sushiRequestedProvider =
    StateNotifierProvider<SushiRequestedNotifier, Set<String>>(
  (ref) => SushiRequestedNotifier(),
);

class SushiRequestedNotifier extends StateNotifier<Set<String>> {
  SushiRequestedNotifier() : super(const {}) {
    _load();
  }

  static const _prefsKey = 'sushi_open_requests';

  static Future<void> clearPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  String _key(int tmdbId, int kind) => '$tmdbId:$kind';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = (prefs.getStringList(_prefsKey) ?? const <String>[]).toSet();
    } catch (_) {
      // A prefs read failure just means no remembered requests — not worth surfacing.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, state.toList());
    } catch (_) {}
  }

  bool contains(int tmdbId, int kind) => state.contains(_key(tmdbId, kind));

  Future<void> mark(int tmdbId, int kind) async {
    final k = _key(tmdbId, kind);
    if (state.contains(k)) return;
    state = {...state, k};
    await _save();
  }

  Future<void> clear(int tmdbId, int kind) async {
    final k = _key(tmdbId, kind);
    if (!state.contains(k)) return;
    state = {...state}..remove(k);
    await _save();
  }
}
