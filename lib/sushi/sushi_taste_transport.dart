import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_taste_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

const _msgTypeTasteRes = 39;

Future<SushiTasteRes?> sushiFetchTaste({
  String watchKind = '',
  int seedPage = 0,
  int personSeedPage = 0,
}) async {
  final label = personSeedPage > 0
      ? 'fetch/people$personSeedPage'
      : seedPage > 1
          ? 'fetch/page$seedPage'
          : 'fetch';
  return _tasteCall(
    sushiEncodeTasteReq(
      watchKind: watchKind,
      seedPage: seedPage,
      personSeedPage: personSeedPage,
    ),
    label: label,
  );
}

Future<SushiTasteRes?> sushiSaveTaste({
  required String watchKind,
  required List<String> genres,
  required List<SushiTasteTitle> likedTitles,
  required List<int> likedPeople,
  required int maxHeight,
  required String audio,
  required String subtitleLang,
  required String subs,
}) async {
  return _tasteCall(
    sushiEncodeTasteReq(
      write: true,
      watchKind: watchKind,
      genres: genres,
      likedTitles: likedTitles,
      likedPeople: likedPeople,
      maxHeight: maxHeight,
      audio: audio,
      subtitleLang: subtitleLang,
      subs: subs,
    ),
    label: 'save',
  );
}

Future<SushiTasteRes?> sushiSearchTastePeople(String query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return null;
  return _tasteCall(
    sushiEncodeTasteReq(personQuery: trimmed),
    label: 'people',
  );
}

Future<SushiTasteRes?> _tasteCall(Uint8List args, {required String label}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null ||
      assignment.pending ||
      assignment.apiSendTargets.isEmpty) {
    debugPrint('[sushi] taste/$label: no assignment yet, skipping');
    return null;
  }

  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText('taste', corr, args);

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: sushiNextApiBot(assignment),
      text: requestText,
      timeoutMs: 20000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr) {
      debugPrint('[sushi] taste/$label: ERR corr=${env.corr}');
      return null;
    }
    if (env.type != _msgTypeTasteRes) {
      debugPrint('[sushi] taste/$label: unexpected msgType=${env.type}');
      return null;
    }
    return SushiTasteRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] taste/$label failed: $e\n$st');
    return null;
  }
}
