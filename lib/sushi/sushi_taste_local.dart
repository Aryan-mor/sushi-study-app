import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-side stamp that the taste wizard finished (or the server said complete).
/// Survives a missing/old apid that does not speak `/taste` yet — without this, a null
/// fetch used to skip the wizard forever.
const _prefsKey = 'sushi_taste_complete_v1';

bool? _memory;

Future<bool> sushiLocalTasteComplete() async {
  if (_memory != null) return _memory!;
  try {
    final prefs = await SharedPreferences.getInstance();
    _memory = prefs.getBool(_prefsKey) ?? false;
  } catch (_) {
    _memory = false;
  }
  return _memory!;
}

Future<void> sushiSetLocalTasteComplete(bool complete) async {
  _memory = complete;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (complete) {
      await prefs.setBool(_prefsKey, true);
    } else {
      await prefs.remove(_prefsKey);
    }
  } catch (e) {
    debugPrint('[sushi] taste local stamp not persisted: $e');
  }
}

/// Call on logout / account switch so the next user is asked again if needed.
Future<void> sushiClearLocalTasteComplete() => sushiSetLocalTasteComplete(false);
