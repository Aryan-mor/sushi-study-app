import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_home_unique.dart';
import 'package:fladder/sushi/sushi_list_transport.dart';

const _prefsKey = 'sushi_not_interested_v1';

/// `tmdbId:kind` keys the viewer hid from Home. Search does not consult this set.
final sushiNotInterestedProvider =
    StateNotifierProvider<SushiNotInterestedNotifier, Set<String>>((ref) {
  final notifier = SushiNotInterestedNotifier();
  sushiNotInterestedSink = notifier.replaceFromServer;
  ref.onDispose(() {
    if (sushiNotInterestedSink == notifier.replaceFromServer) {
      sushiNotInterestedSink = null;
    }
  });
  return notifier;
});

class SushiNotInterestedNotifier extends StateNotifier<Set<String>> {
  SushiNotInterestedNotifier() : super(const {}) {
    _load();
  }

  var _serverApplied = false;

  /// Marks still waiting for Home to echo them. A Home reply that has not caught up must not
  /// wipe a tap that just landed.
  final Map<String, bool> _pending = {};

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsKey) ?? const <String>[];
    if (_serverApplied) return;
    state = stored.toSet();
  }

  Future<void> _persist(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, keys.toList());
  }

  /// HomeRes.not_interested. Full snapshot, plus any tap the server has not echoed yet.
  void replaceFromServer(List<SushiNotInterestedTitle> titles) {
    _serverApplied = true;
    final keys = {
      for (final title in titles)
        if (title.tmdbId > 0 && title.kind != SushiKind.unspecified)
          '${title.tmdbId}:${sushiKindToWire(title.kind)}',
    };
    final still = <String, bool>{};
    for (final entry in _pending.entries) {
      if (keys.contains(entry.key) == entry.value) continue;
      still[entry.key] = entry.value;
      if (entry.value) {
        keys.add(entry.key);
      } else {
        keys.remove(entry.key);
      }
    }
    _pending
      ..clear()
      ..addAll(still);
    state = keys;
    _persist(keys);
  }

  bool isHidden(ItemBaseModel item) => state.contains(sushiHomeItemKey(item));

  Future<void> setHidden(ItemBaseModel item, bool on) async {
    final id = sushiContinueIdentity(item);
    if (id == null) return;
    final key = '${id.tmdbId}:${sushiKindToWire(id.kind)}';
    _pending[key] = on;
    final next = {...state};
    if (on) {
      next.add(key);
    } else {
      next.remove(key);
    }
    state = next;
    await _persist(next);
    await sushiSendNotInterestedEvent(
      tmdbId: id.tmdbId,
      kind: sushiKindToWire(id.kind),
      on: on,
    );
  }
}

List<ItemBaseModel> sushiDropNotInterested(Iterable<ItemBaseModel> items, Set<String> hidden) {
  if (hidden.isEmpty) return items is List<ItemBaseModel> ? items : items.toList();
  return [for (final item in items) if (!hidden.contains(sushiHomeItemKey(item))) item];
}
