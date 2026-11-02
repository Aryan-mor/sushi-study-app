import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_prefs_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

const _msgTypePrefsRes = 29;

String? _cachedGeminiKey;
bool _cachedHasKey = false;
bool _fetched = false;

/// Process-memory cache of the user Gemini key. Never written to disk (doc 15 §12).
void sushiClearGeminiKeyCache() {
  _cachedGeminiKey = null;
  _cachedHasKey = false;
  _fetched = false;
}

Future<String?> sushiGeminiApiKey({bool force = false}) async {
  if (_fetched && !force) {
    return _cachedHasKey ? _cachedGeminiKey : null;
  }
  final prefs = await sushiFetchPrefs();
  if (prefs == null) return _cachedHasKey ? _cachedGeminiKey : null;
  return prefs.hasGeminiKey && prefs.geminiApiKey.isNotEmpty ? prefs.geminiApiKey : null;
}

Future<bool> sushiHasGeminiApiKey({bool force = false}) async {
  final key = await sushiGeminiApiKey(force: force);
  return key != null && key.isNotEmpty;
}

Future<SushiPrefsRes?> sushiFetchPrefs() async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null ||
      assignment.pending ||
      assignment.apiSendTargets.isEmpty) {
    debugPrint('[sushi] prefs: no assignment yet, skipping');
    return null;
  }

  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText('prefs', corr, Uint8List(0));

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: sushiNextApiBot(assignment),
      text: requestText,
      timeoutMs: 15000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr) {
      debugPrint('[sushi] prefs: server returned ERR (corr=${env.corr})');
      return null;
    }
    if (env.type != _msgTypePrefsRes) {
      debugPrint('[sushi] prefs: unexpected msgType=${env.type} (corr=${env.corr})');
      return null;
    }
    final prefs = SushiPrefsRes.decode(env.payload);
    _fetched = true;
    _cachedHasKey = prefs.hasGeminiKey && prefs.geminiApiKey.isNotEmpty;
    _cachedGeminiKey = _cachedHasKey ? prefs.geminiApiKey : null;
    debugPrint(
      '[sushi] prefs: has_key=${prefs.hasGeminiKey} key_len=${prefs.geminiApiKey.length}',
    );
    return prefs;
  } catch (e, st) {
    debugPrint('[sushi] prefs failed: $e\n$st');
    return null;
  }
}
