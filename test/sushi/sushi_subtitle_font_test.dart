import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/settings/subtitle_settings_model.dart';
import 'package:fladder/sushi/playback/sushi_subtitle_font.dart';

void main() {
  group('SushiSubtitleFont', () {
    test('detects Persian language tags', () {
      expect(SushiSubtitleFont.isPersianOrArabicLanguage('fa'), isTrue);
      expect(SushiSubtitleFont.isPersianOrArabicLanguage('fas'), isTrue);
      expect(SushiSubtitleFont.isPersianOrArabicLanguage('per'), isTrue);
      expect(SushiSubtitleFont.isPersianOrArabicLanguage('en'), isFalse);
      expect(SushiSubtitleFont.isPersianOrArabicLanguage('Unknown'), isFalse);
    });

    test('cue background uses 2px horizontal padding', () {
      expect(SushiSubtitleFont.cueBackgroundHorizontalPadding, 2);
    });

    test('Persian track language forces RTL even on mixed ASCII punctuation', () {
      expect(
        SushiSubtitleFont.textDirectionFor('سلام دنیا.', language: 'fa'),
        TextDirection.rtl,
      );
      expect(
        SushiSubtitleFont.textDirectionFor('Hello.', language: 'fa'),
        TextDirection.rtl,
      );
      expect(
        SushiSubtitleFont.textDirectionFor('Hello.', language: 'en'),
        TextDirection.ltr,
      );
    });

    test('isolateForPaint wraps RTL cues so ASCII punctuation stays in embedding', () {
      const cue = 'سلام دنیا.';
      final isolated = SushiSubtitleFont.isolateForPaint(cue, TextDirection.rtl);
      expect(isolated, startsWith('\u202B'));
      expect(isolated, endsWith('\u202C'));
      expect(isolated, contains(cue));
      expect(
        SushiSubtitleFont.isolateForPaint(cue, TextDirection.ltr),
        cue,
      );
    });

    test('prefers track language over script', () {
      expect(
        SushiSubtitleFont.shouldUsePersianFont(language: 'fa', text: 'Hello'),
        isTrue,
      );
    });

    test('default settings use white fill with thin black outline', () {
      expect(SushiSubtitleFont.defaultSettings.color, equals(Colors.white));
      expect(SushiSubtitleFont.defaultSettings.outlineSize, 1);
      expect(SushiSubtitleFont.defaultSettings.backGroundColor, equals(SushiSubtitleFont.defaultBackground));
      expect(SushiSubtitleFont.defaultBackground.a, closeTo(0.55, 0.001));
      expect(SushiSubtitleFont.defaultBackground.r, 0);
    });

    test('migrate applies boxed default only to unversioned transparent saves', () {
      const old = SubtitleSettingsModel(
        color: Colors.white,
        outlineSize: 1,
        backGroundColor: Color.fromARGB(0, 0, 0, 0),
      );
      final migrated = SushiSubtitleFont.migrateLoadedSettings(old, schema: 1);
      expect(migrated.backGroundColor, equals(SushiSubtitleFont.defaultBackground));

      final keptTransparent = SushiSubtitleFont.migrateLoadedSettings(old, schema: 2);
      expect(keptTransparent.backGroundColor.a, 0);

      const custom = SubtitleSettingsModel(backGroundColor: Color.fromRGBO(0, 0, 0, 0.2));
      expect(
        SushiSubtitleFont.migrateLoadedSettings(custom, schema: 1).backGroundColor.a,
        closeTo(0.2, 0.001),
      );
    });

    test('assForceStyle includes outline and Persian font name', () {
      const noBox = SubtitleSettingsModel(
        color: Colors.white,
        outlineColor: Color.fromRGBO(0, 0, 0, 0.85),
        outlineSize: 1,
        backGroundColor: Color.fromARGB(0, 0, 0, 0),
      );
      final style = SushiSubtitleFont.assForceStyle(noBox, language: 'fa');
      expect(style, contains('FontName=Vazirmatn'));
      expect(style, contains('Outline=1'));
      expect(style, contains('OutlineColour='));
      expect(style, contains('BorderStyle=1'));
    });

    test('assForceStyle uses opaque box when background has alpha', () {
      final style = SushiSubtitleFont.assForceStyle(
        SushiSubtitleFont.defaultSettings,
        language: 'fa',
      );
      expect(style, contains('BorderStyle=3'));
      expect(style, contains('BackColour='));
    });
  });
}
