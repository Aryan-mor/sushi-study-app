import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/sushi/subtitles/sushi_subtitle_actions.dart';

void main() {
  test('Automatic tries at most three ranked packs', () {
    expect(sushiAutoSubtitlePackAttempts, 3);
    expect(sushiSubtitlePackAttemptWindow([1, 2]), [1, 2]);
    expect(sushiSubtitlePackAttemptWindow([1, 2, 3]), [1, 2, 3]);
    expect(sushiSubtitlePackAttemptWindow([1, 2, 3, 4, 5]), [1, 2, 3]);
    expect(sushiSubtitlePackAttemptWindow(<int>[]), isEmpty);
  });

  test('cut type prefers the release family over softsub', () {
    expect(sushiSubtitleCutType('1080p SoftSub'), 'softsub');
    expect(sushiSubtitleCutType('Friends.S03.1080p.BluRay.x265'), 'bluray');
    expect(sushiSubtitleCutType('BluRay SoftSub'), 'bluray');
    expect(sushiSubtitleCutType('Movie.2026.AMZN.WEB'), 'web');
    expect(sushiSubtitleCutType('Movie.2026.TELESYNC.1080p'), 'telesync');
    expect(sushiSubtitleCutType('Movie.2026.CAM-Rip.720p'), 'cam');
    expect(sushiSubtitleCutType('1080p'), '');
    expect(sushiSubtitleCutType('webcam'), '');
  });

  test('timeline seconds reads the last cue end', () {
    const text = '1\n00:00:01,000 --> 00:00:02,000\nhi\n\n2\n00:22:30,000 --> 00:22:58,000\nbye\n';
    expect(sushiSubtitleTimelineSeconds(text), 22 * 60 + 58);
  });
}
