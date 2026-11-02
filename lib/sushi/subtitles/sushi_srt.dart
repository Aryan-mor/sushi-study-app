/// Minimal SRT cue parser / writer for Sushi translate.
///
/// Timestamps stay local. Only [SushiSrtCue.text] is sent to Gemini.

class SushiSrtCue {
  const SushiSrtCue({required this.index, required this.timing, required this.text});

  final int index;
  final String timing;
  final String text;
}

final _cueSplit = RegExp(r'\n\s*\n');
final _indexLine = RegExp(r'^\d+\s*$');

List<SushiSrtCue> sushiParseSrt(String raw) {
  final norm = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (norm.isEmpty) return const [];
  final out = <SushiSrtCue>[];
  var n = 1;
  for (final block in norm.split(_cueSplit)) {
    final lines = block.split('\n').map((l) => l.trimRight()).toList();
    if (lines.isEmpty) continue;
    var i = 0;
    if (_indexLine.hasMatch(lines.first.trim())) i = 1;
    if (i >= lines.length) continue;
    final timing = lines[i].trim();
    if (!timing.contains('-->')) continue;
    final text = lines.skip(i + 1).join('\n').trim();
    if (text.isEmpty) continue;
    out.add(SushiSrtCue(index: n, timing: timing, text: text));
    n++;
  }
  return out;
}

String sushiBuildSrt(List<SushiSrtCue> cues) {
  final buf = StringBuffer();
  for (var i = 0; i < cues.length; i++) {
    final c = cues[i];
    buf
      ..writeln('${i + 1}')
      ..writeln(c.timing)
      ..writeln(c.text);
    if (i != cues.length - 1) buf.writeln();
  }
  return buf.toString();
}

/// Packs cue texts into batches under [maxChars] for one Gemini call each.
List<List<SushiSrtCue>> sushiBatchSrtCues(List<SushiSrtCue> cues, {int maxChars = 24000}) {
  if (cues.isEmpty) return const [];
  final batches = <List<SushiSrtCue>>[];
  var cur = <SushiSrtCue>[];
  var size = 0;
  for (final c in cues) {
    final add = c.text.length + 8;
    if (cur.isNotEmpty && size + add > maxChars) {
      batches.add(cur);
      cur = <SushiSrtCue>[];
      size = 0;
    }
    cur.add(c);
    size += add;
  }
  if (cur.isNotEmpty) batches.add(cur);
  return batches;
}

/// `1. line` numbered payload Gemini is asked to translate, one cue per line.
String sushiNumberedCuePayload(List<SushiSrtCue> cues) {
  final buf = StringBuffer();
  for (var i = 0; i < cues.length; i++) {
    final flat = cues[i].text.replaceAll('\n', ' | ');
    buf.writeln('${i + 1}. $flat');
  }
  return buf.toString();
}

/// Maps numbered reply lines back onto [cues]. Missing lines keep the original text.
List<SushiSrtCue> sushiApplyNumberedTranslations(List<SushiSrtCue> cues, String reply) {
  final map = <int, String>{};
  for (final raw in reply.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = RegExp(r'^(\d+)\.\s*(.*)$').firstMatch(line);
    if (m == null) continue;
    final i = int.tryParse(m.group(1)!);
    if (i == null) continue;
    var text = m.group(2)!.trim();
    if (text.isEmpty) continue;
    text = text.replaceAll(' | ', '\n');
    map[i] = text;
  }
  return [
    for (var i = 0; i < cues.length; i++)
      SushiSrtCue(
        index: cues[i].index,
        timing: cues[i].timing,
        text: map[i + 1] ?? cues[i].text,
      ),
  ];
}

Duration? sushiSrtCueStart(SushiSrtCue cue) {
  final m = RegExp(r'^(\d+):(\d{2}):(\d{2})[,.](\d+)').firstMatch(cue.timing.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  final sec = int.parse(m.group(3)!);
  var ms = int.parse(m.group(4)!);
  switch (m.group(4)!.length) {
    case 1:
      ms *= 100;
    case 2:
      ms *= 10;
  }
  return Duration(hours: h, minutes: min, seconds: sec, milliseconds: ms);
}

class SushiSrtWindow {
  const SushiSrtWindow({required this.now, required this.later});
  final List<SushiSrtCue> now;
  final List<SushiSrtCue> later;
}

/// Cues around [position] for a first Gemini call. Rest can translate in the background.
SushiSrtWindow sushiSplitCuesAroundPlayback(
  List<SushiSrtCue> cues,
  Duration position, {
  Duration ahead = const Duration(minutes: 12),
  Duration behind = const Duration(seconds: 20),
  int maxNow = 150,
}) {
  if (cues.isEmpty) return const SushiSrtWindow(now: [], later: []);
  final start = position < behind ? Duration.zero : position - behind;
  final end = position + ahead;
  final now = <SushiSrtCue>[];
  final later = <SushiSrtCue>[];
  for (final c in cues) {
    final t = sushiSrtCueStart(c) ?? Duration.zero;
    if (t >= start && t < end && now.length < maxNow) {
      now.add(c);
    } else {
      later.add(c);
    }
  }
  if (now.isNotEmpty) return SushiSrtWindow(now: now, later: later);
  final after = [for (final c in cues) if ((sushiSrtCueStart(c) ?? Duration.zero) >= position) c];
  final pick = (after.isNotEmpty ? after : cues).take(maxNow).toList();
  final picked = pick.map((c) => c.timing).toSet();
  return SushiSrtWindow(
    now: pick,
    later: [for (final c in cues) if (!picked.contains(c.timing)) c],
  );
}

String sushiMergeSrtByTiming(List<SushiSrtCue> a, List<SushiSrtCue> b) {
  final all = [...a, ...b]..sort((x, y) {
        final dx = sushiSrtCueStart(x) ?? Duration.zero;
        final dy = sushiSrtCueStart(y) ?? Duration.zero;
        return dx.compareTo(dy);
      });
  return sushiBuildSrt(all);
}

/// Turns a subtitle file into UTF-8 SRT/ASS text mpv can parse.
///
/// SubDL often ships UTF-16 LE (BOM `FF FE`). Server `decodeText` used to treat
/// those bytes as Windows-1256, so the cached Telegram copy starts with `ے‏1`
/// (`0xFF`/`0xFE` in CP1256) and has NULs between ASCII — `-->` never appears,
/// cues parse as empty, overlay stays blank (`textSeen=false`).
String sushiNormalizeSubtitleText(String raw) {
  if (raw.isEmpty) return raw;
  if (!raw.contains('\u0000') && raw.contains('-->')) {
    return raw.replaceAll('\uFEFF', '');
  }
  final recovered = _recoverUtf16LeFromCp1256(raw);
  if (recovered != null && recovered.contains('-->')) {
    return recovered.replaceAll('\uFEFF', '');
  }
  return raw.replaceAll('\uFEFF', '');
}

/// Windows-1256 decode of bytes 0x80..0xFF (golang.org/x/text charmap).
const _cp1256High =
    '\u20ac\u067e\u201a\u0192\u201e\u2026\u2020\u2021\u02c6\u2030\u0679\u2039\u0152\u0686\u0698\u0688\u06af\u2018\u2019\u201c\u201d\u2022\u2013\u2014\u06a9\u2122\u0691\u203a\u0153\u200c\u200d\u06ba\xa0\u060c\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\u06be\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\u061b\xbb\xbc\xbd\xbe\u061f\u06c1\u0621\u0622\u0623\u0624\u0625\u0626\u0627\u0628\u0629\u062a\u062b\u062c\u062d\u062e\u062f\u0630\u0631\u0632\u0633\u0634\u0635\u0636\xd7\u0637\u0638\u0639\u063a\u0640\u0641\u0642\u0643\xe0\u0644\xe2\u0645\u0646\u0647\u0648\xe7\xe8\xe9\xea\xeb\u0649\u064a\xee\xef\u064b\u064c\u064d\u064e\xf4\u064f\u0650\xf7\u0651\xf9\u0652\xfb\xfc\u200e\u200f\u06d2';

String? _recoverUtf16LeFromCp1256(String s) {
  if (!s.contains('\u0000') && !s.startsWith('\u06d2\u200f') && !s.startsWith('\u00ff\u00fe')) {
    return null;
  }
  final bytes = _encodeWindows1256(s);
  if (bytes == null || bytes.length < 4) return null;
  var start = 0;
  var little = true;
  if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
    start = 2;
  } else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
    start = 2;
    little = false;
  }
  final n = bytes.length - start;
  if (n < 2) return null;
  final units = <int>[];
  for (var i = start; i + 1 < bytes.length; i += 2) {
    units.add(little ? bytes[i] | (bytes[i + 1] << 8) : bytes[i + 1] | (bytes[i] << 8));
  }
  return String.fromCharCodes(units);
}

List<int>? _encodeWindows1256(String s) {
  final out = <int>[];
  for (final r in s.runes) {
    if (r <= 0x7F) {
      out.add(r);
      continue;
    }
    final i = _cp1256High.indexOf(String.fromCharCode(r));
    if (i < 0) return null;
    out.add(0x80 + i);
  }
  return out;
}
