import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/subtitles/sushi_srt.dart';

void main() {
  const raw = '''1
00:00:01,000 --> 00:00:02,500
Hello
world

2
00:00:03,000 --> 00:00:04,000
Bye
''';

  test('parse/build round-trip keeps timing and text', () {
    final cues = sushiParseSrt(raw);
    expect(cues, hasLength(2));
    expect(cues[0].timing, '00:00:01,000 --> 00:00:02,500');
    expect(cues[0].text, 'Hello\nworld');
    expect(sushiParseSrt(sushiBuildSrt(cues)), hasLength(2));
    expect(sushiBuildSrt(cues), contains('Hello\nworld'));
  });

  test('batch splits when maxChars is small', () {
    final cues = sushiParseSrt(raw);
    final batches = sushiBatchSrtCues(cues, maxChars: 20);
    expect(batches, hasLength(2));
    expect(batches[0], hasLength(1));
  });

  test('default batch packs a short file into one request', () {
    final cues = List.generate(
      40,
      (i) => SushiSrtCue(
        index: i + 1,
        timing: '00:00:00,000 --> 00:00:01,000',
        text: 'Hi',
      ),
    );
    expect(sushiBatchSrtCues(cues), hasLength(1));
  });

  test('numbered payload maps translations back onto cues', () {
    final cues = sushiParseSrt(raw);
    final payload = sushiNumberedCuePayload(cues);
    expect(payload, contains('1. Hello | world'));
    expect(payload, contains('2. Bye'));
    final out = sushiApplyNumberedTranslations(cues, '1. سلام | دنیا\n2. خداحافظ\n');
    expect(out[0].text, 'سلام\nدنیا');
    expect(out[0].timing, cues[0].timing);
    expect(out[1].text, 'خداحافظ');
  });

  test('missing numbered lines keep the original text', () {
    final cues = sushiParseSrt(raw);
    final out = sushiApplyNumberedTranslations(cues, '2. فقط دومی');
    expect(out[0].text, cues[0].text);
    expect(out[1].text, 'فقط دومی');
  });

  test('split around playback takes nearby cues first', () {
    final cues = [
      for (var i = 0; i < 5; i++)
        SushiSrtCue(
          index: i + 1,
          timing: '00:0$i:00,000 --> 00:0$i:01,000',
          text: 'c$i',
        ),
    ];
    final w = sushiSplitCuesAroundPlayback(
      cues,
      const Duration(minutes: 2),
      ahead: const Duration(minutes: 2),
      behind: Duration.zero,
      maxNow: 10,
    );
    expect(w.now.map((c) => c.text).toList(), ['c2', 'c3']);
    expect(w.later.map((c) => c.text).toList(), ['c0', 'c1', 'c4']);
  });

  test('normalizes UTF-16 LE misread as Windows-1256', () {
    const srt = '1\n00:00:01,000 --> 00:00:02,000\nسلام\n';
    final utf16 = <int>[0xFF, 0xFE];
    for (final u in srt.codeUnits) {
      utf16.add(u & 0xFF);
      utf16.add((u >> 8) & 0xFF);
    }
    const high =
        '\u20ac\u067e\u201a\u0192\u201e\u2026\u2020\u2021\u02c6\u2030\u0679\u2039\u0152\u0686\u0698\u0688\u06af\u2018\u2019\u201c\u201d\u2022\u2013\u2014\u06a9\u2122\u0691\u203a\u0153\u200c\u200d\u06ba\xa0\u060c\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\u06be\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\u061b\xbb\xbc\xbd\xbe\u061f\u06c1\u0621\u0622\u0623\u0624\u0625\u0626\u0627\u0628\u0629\u062a\u062b\u062c\u062d\u062e\u062f\u0630\u0631\u0632\u0633\u0634\u0635\u0636\xd7\u0637\u0638\u0639\u063a\u0640\u0641\u0642\u0643\xe0\u0644\xe2\u0645\u0646\u0647\u0648\xe7\xe8\xe9\xea\xeb\u0649\u064a\xee\xef\u064b\u064c\u064d\u064e\xf4\u064f\u0650\xf7\u0651\xf9\u0652\xfb\xfc\u200e\u200f\u06d2';
    final mojibake = String.fromCharCodes([
      for (final b in utf16) b < 0x80 ? b : high.codeUnitAt(b - 0x80),
    ]);
    expect(mojibake, startsWith('\u06d2\u200f'));
    final got = sushiNormalizeSubtitleText(mojibake);
    expect(got, contains('-->'));
    expect(got, contains('سلام'));
    expect(sushiParseSrt(got), isNotEmpty);
  });
}
