import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/sushi/playback/sushi_subtitle_paint.dart';

void main() {
  test('desktop libass SRT paints Flutter overlay', () {
    expect(
      sushiSubtitlePaintPath(libassEnabled: true, isAss: false, textEmpty: false),
      'flutter_overlay',
    );
  });

  test('ASS with libass burns in mpv', () {
    expect(
      sushiSubtitlePaintPath(libassEnabled: true, isAss: true, textEmpty: false),
      'libass_ass_burn',
    );
  });

  test('empty cue does not paint overlay', () {
    expect(
      sushiSubtitlePaintPath(libassEnabled: true, isAss: false, textEmpty: true),
      'empty',
    );
  });

  test('libass off SRT still uses overlay', () {
    expect(
      sushiSubtitlePaintPath(libassEnabled: false, isAss: false, textEmpty: false),
      'flutter_overlay',
    );
  });
}
