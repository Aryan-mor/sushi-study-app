import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/sushi/playback/sushi_persian_language.dart';

void main() {
  group('SushiPersianLanguage', () {
    test('detects Persian language tags and names', () {
      expect(SushiPersianLanguage.isPersianLanguage('fa'), isTrue);
      expect(SushiPersianLanguage.isPersianLanguage('fas'), isTrue);
      expect(SushiPersianLanguage.isPersianLanguage('Persian'), isTrue);
      expect(SushiPersianLanguage.isPersianLanguage('Farsi'), isTrue);
      expect(SushiPersianLanguage.isPersianLanguage('فارسی'), isTrue);
      expect(SushiPersianLanguage.isPersianLanguage('en'), isFalse);
      expect(SushiPersianLanguage.isPersianLanguage('ar'), isFalse);
    });

    test('showIranFlagForSubtitle respects off track', () {
      expect(
        SushiPersianLanguage.showIranFlagForSubtitle(
          subtitleLanguage: 'fa',
          playbackModel: null,
          subtitleIndex: -1,
        ),
        isFalse,
      );
      expect(
        SushiPersianLanguage.showIranFlagForSubtitle(
          subtitleLanguage: 'fa',
          playbackModel: null,
          subtitleIndex: 2,
        ),
        isTrue,
      );
    });
  });
}
