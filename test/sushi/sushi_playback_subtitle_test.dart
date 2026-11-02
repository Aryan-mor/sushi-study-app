import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/sushi/playback/sushi_persian_language.dart';
import 'package:fladder/sushi/sushi_account_playback_pref.dart';
import 'package:fladder/sushi/sushi_playback_subtitle.dart';

SubStreamModel _sub({
  required int index,
  required String language,
  String displayTitle = '',
}) {
  return SubStreamModel(
    name: displayTitle,
    id: '$index',
    title: displayTitle,
    displayTitle: displayTitle.isEmpty ? language : displayTitle,
    language: language,
    codec: 'subrip',
    isDefault: false,
    isExternal: false,
    index: index,
  );
}

void main() {
  test('hardsub media source defaults subtitle Off', () {
    final streams = [
      SubStreamModel.no(),
    ];
    expect(
      sushiResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: 2,
        subStreams: streams,
        mediaSourceName: '1080p - hard sub (Persian)',
      ),
      -1,
    );
  });

  test('چسبیده without muxed srt is treated as hardsub at playback', () {
    expect(
      sushiMediaSourceLooksHardSub('720p HDTS زیرنویس_فارسی_چسبیده', subStreams: [SubStreamModel.no()]),
      isTrue,
    );
  });

  test('چسبیده with a muxed srt is not hardsub', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(sushiMediaSourceLooksHardSub('زیرنویس_فارسی_چسبیده', subStreams: streams), isFalse);
    expect(
      sushiResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: 2,
        subStreams: streams,
        mediaSourceName: '720p HDTS زیرنویس_فارسی_چسبیده',
      ),
      2,
    );
  });

  test('softsub still prefers Persian when no selection', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'eng', displayTitle: 'English'),
      _sub(index: 3, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      sushiResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: null,
        subStreams: streams,
        mediaSourceName: '1080p - soft sub',
      ),
      3,
    );
  });

  test('server Off is overridden by an available Persian softsub', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      sushiResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: -1,
        subStreams: streams,
        mediaSourceName: '1080p - soft sub',
      ),
      2,
    );
  });

  test('server Off with no Persian available stays Off', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'eng', displayTitle: 'English'),
    ];
    expect(
      sushiResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: -1,
        subStreams: streams,
        mediaSourceName: '1080p - soft sub',
      ),
      -1,
    );
  });

  test('server default is non-Persian (English) but Persian available -> Persian wins', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'eng', displayTitle: 'English'),
      _sub(index: 3, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      sushiResolveSubtitleStreamIndex(
        selectedIndex: 2,
        serverDefaultIndex: 2,
        subStreams: streams,
        mediaSourceName: '1080p - soft sub',
      ),
      3,
    );
  });

  test('explicit user selection wins over hardsub Off', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      sushiResolveSubtitleStreamIndex(
        selectedIndex: 2,
        serverDefaultIndex: -1,
        subStreams: streams,
        mediaSourceName: '1080p HardSub',
      ),
      2,
    );
  });

  test('english-only softsub is not treated as Farsi', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'eng', displayTitle: 'English'),
    ];
    expect(sushiHasPersianSoftSub(streams), isFalse);
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: false),
      SushiStartSubtitle.automaticOnline,
    );
  });

  test('fa label is the start track; online only when there is no fa label', () {
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: true),
      SushiStartSubtitle.persianSoft,
    );
    expect(
      sushiStartSubtitleSteps(hardSub: false, hasPersianSoft: true, aiSet: false),
      [SushiStartSubtitleStep.persianSoft],
    );
    expect(
      sushiStartSubtitleSteps(hardSub: false, hasPersianSoft: true, aiSet: true),
      [SushiStartSubtitleStep.persianSoft],
    );
    expect(
      sushiStartSubtitleSteps(hardSub: false, hasPersianSoft: false, aiSet: true),
      [SushiStartSubtitleStep.automaticOnline, SushiStartSubtitleStep.aiTranslate],
    );
    expect(
      sushiStartSubtitleChoice(hardSub: true, hasPersianSoft: false),
      SushiStartSubtitle.off,
    );
    expect(
      sushiStartSubtitleChoice(hardSub: true, hasPersianSoft: true),
      SushiStartSubtitle.off,
    );
    expect(
      sushiStartSubtitleSteps(hardSub: true, hasPersianSoft: true, aiSet: true),
      isEmpty,
    );
    expect(sushiHasPersianSoftSub([_sub(index: 3, language: 'fa', displayTitle: 'Persian')]), isTrue);
    expect(sushiHasPersianSoftSub([SubStreamModel.no()]), isFalse);
  });

  test('catalog-only fa lang code is not a playable Farsi softsub', () {
    final stub = SubStreamModel(
      name: 'FA',
      id: 'sushi_sub_1_0',
      title: 'FA',
      displayTitle: 'FA',
      language: 'fa',
      codec: '',
      isDefault: true,
      isExternal: false,
      index: 0,
    );
    expect(sushiSubtitleTrackIsPlayable(stub), isFalse);
    expect(sushiHasPersianSoftSub([SubStreamModel.no(), stub]), isFalse);
    expect(
      sushiStartSubtitleChoice(
        hardSub: false,
        hasPersianSoft: sushiHasPersianSoftSub([SubStreamModel.no(), stub]),
      ),
      SushiStartSubtitle.automaticOnline,
    );
    final plan = sushiPlanStartSubtitle(
      subStreams: [SubStreamModel.no(), stub],
      mediaSourceName: '1080p SoftSub',
    );
    expect(plan.choice, SushiStartSubtitle.persianSoft);
    expect(plan.index, 0);
  });

  test('sushiPreferredLangStreamIndex matches account lang not just fa', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 1, language: 'fa', displayTitle: 'FA'),
      _sub(index: 2, language: 'en', displayTitle: 'EN'),
      _sub(index: 3, language: 'es', displayTitle: 'ES'),
    ];
    expect(sushiPreferredLangStreamIndex(streams, 'en'), 2);
    expect(sushiPreferredLangStreamIndex(streams, 'es'), 3);
    expect(sushiPreferredLangStreamIndex(streams, 'fa'), 1);
    expect(sushiPreferredLangStreamIndex(streams, 'de'), isNull);
  });

  test('fa label wins over a stale Off flag', () {
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: true, subtitleOff: true),
      SushiStartSubtitle.persianSoft,
    );
    expect(
      sushiStartSubtitleChoice(hardSub: true, hasPersianSoft: true, subtitleOff: true),
      SushiStartSubtitle.off,
    );
  });

  test('English hardsub stays Off; audio language does not reopen Automatic', () {
    expect(
      sushiStartSubtitleChoice(hardSub: true, hasPersianSoft: false, isEnglishAudio: true),
      SushiStartSubtitle.off,
    );
    expect(
      sushiStartSubtitleSteps(
        hardSub: true,
        hasPersianSoft: true,
        aiSet: true,
      ),
      isEmpty,
    );
    expect(
      sushiStartSubtitleChoice(hardSub: true, hasPersianSoft: false, isEnglishAudio: false),
      SushiStartSubtitle.off,
    );
  });

  test('bare 720p label is unknown, not hardsub', () {
    expect(sushiMediaSourceLooksHardSub('720p'), isFalse);
  });

  test('HDTS filename is treated as hardsub', () {
    expect(
      sushiMediaSourceLooksHardSub(
        'Spider_Man_Brand_New_Day_2026_720P_Hdts_MyMoviz_video_converter.mp4',
      ),
      isTrue,
    );
  });

  test('Iranian content skips auto subtitle entirely, even with hardsub off', () {
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: false, isIranian: true),
      SushiStartSubtitle.off,
    );
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: true, isEnglishAudio: true, isIranian: true),
      SushiStartSubtitle.off,
    );
  });

  test('en or unknown label is sniffed; fa and other languages are not', () {
    expect(sushiSubtitleLanguageNeedsScriptSniff('en'), isTrue);
    expect(sushiSubtitleLanguageNeedsScriptSniff('eng'), isTrue);
    expect(sushiSubtitleLanguageNeedsScriptSniff(''), isTrue);
    expect(sushiSubtitleLanguageNeedsScriptSniff('und'), isTrue);
    expect(sushiSubtitleLanguageNeedsScriptSniff('unknown'), isTrue);
    expect(sushiSubtitleLanguageNeedsScriptSniff('fa'), isFalse);
    expect(sushiSubtitleLanguageNeedsScriptSniff('fr'), isFalse);
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: false, needsScriptSniff: true),
      SushiStartSubtitle.sniffEmbedded,
    );
    final en = _sub(index: 2, language: 'en', displayTitle: 'EN');
    final plan = sushiPlanStartSubtitle(
      subStreams: [SubStreamModel.no(), en],
      mediaSourceName: '1080p SoftSub',
    );
    expect(plan.choice, SushiStartSubtitle.sniffEmbedded);
    expect(plan.index, 2);
  });

  test('subtitle sample is Persian only when Arabic script is the body', () {
    expect(sushiSubtitleSampleLooksPersian('سلام این یک جمله فارسی برای تست زیرنویس است'), isTrue);
    expect(sushiSubtitleSampleLooksPersian('This is a full English subtitle line about the plot'), isFalse);
    expect(sushiSubtitleSampleLooksPersian('Translated by علی\nRoss: We were on a break!'), isFalse);
    expect(sushiSubtitleSampleLooksPersian('سلام'), isFalse);
    expect(sushiSubtitleSampleRejectsPersian(''), isFalse);
    expect(sushiSubtitleSampleRejectsPersian('سلام'), isFalse);
    expect(sushiSubtitleSampleRejectsPersian('This is a full English subtitle line about the plot'), isTrue);
  });

  test('with subtitles: non-Persian goes auto online, Persian is hard then soft then online', () {
    const enOn = SushiAccountPlaybackPref(
      audio: SushiAudioPref.original,
      subtitleLang: 'en',
      subs: SushiSubsPref.on,
    );
    const faOn = SushiAccountPlaybackPref(
      audio: SushiAudioPref.original,
      subtitleLang: 'fa',
      subs: SushiSubsPref.on,
    );
    const faOff = SushiAccountPlaybackPref(
      audio: SushiAudioPref.original,
      subtitleLang: 'fa',
      subs: SushiSubsPref.off,
    );
    expect(
      sushiStartSubtitleChoice(
        hardSub: false,
        hasPersianSoft: true,
        needsScriptSniff: true,
        account: enOn,
      ),
      SushiStartSubtitle.automaticOnline,
    );
    final en = _sub(index: 2, language: 'en', displayTitle: 'EN');
    final enPlan = sushiPlanStartSubtitle(
      subStreams: [SubStreamModel.no(), en],
      mediaSourceName: '1080p SoftSub',
      account: enOn,
    );
    expect(enPlan.choice, SushiStartSubtitle.automaticOnline);
    expect(enPlan.index, -1);

    expect(
      sushiStartSubtitleChoice(hardSub: true, hasPersianSoft: false, account: faOn),
      SushiStartSubtitle.off,
    );
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: true, account: faOn),
      SushiStartSubtitle.persianSoft,
    );
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: false, account: faOn),
      SushiStartSubtitle.automaticOnline,
    );
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: true, account: faOff),
      SushiStartSubtitle.off,
    );
  });

  test('saved title pick replays off, language, automatic, and AI', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'en', displayTitle: 'English'),
      _sub(index: 3, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      sushiPlanFromTitleSubtitleMemory(
        memory: const SushiTitleSubtitleMemory(kind: SushiTitleSubtitleKind.off),
        subStreams: streams,
      ).choice,
      SushiStartSubtitle.off,
    );
    final track = sushiPlanFromTitleSubtitleMemory(
      memory: const SushiTitleSubtitleMemory(kind: SushiTitleSubtitleKind.track, language: 'en'),
      subStreams: streams,
    );
    expect(track.choice, SushiStartSubtitle.persianSoft);
    expect(track.index, 2);
    final missing = sushiPlanFromTitleSubtitleMemory(
      memory: const SushiTitleSubtitleMemory(kind: SushiTitleSubtitleKind.track, language: 'de'),
      subStreams: streams,
    );
    expect(missing.choice, SushiStartSubtitle.off);
    expect(missing.index, -1);
    expect(
      sushiPlanFromTitleSubtitleMemory(
        memory: const SushiTitleSubtitleMemory(kind: SushiTitleSubtitleKind.automatic),
        subStreams: streams,
      ).choice,
      SushiStartSubtitle.automaticOnline,
    );
    expect(
      sushiPlanFromTitleSubtitleMemory(
        memory: const SushiTitleSubtitleMemory(kind: SushiTitleSubtitleKind.ai),
        subStreams: streams,
      ).choice,
      SushiStartSubtitle.aiTranslate,
    );
  });

  test('sushiIsEnglishLanguage matches en/eng/en-* only', () {
    expect(sushiIsEnglishLanguage('en'), isTrue);
    expect(sushiIsEnglishLanguage('eng'), isTrue);
    expect(sushiIsEnglishLanguage('en-US'), isTrue);
    expect(sushiIsEnglishLanguage('fa'), isFalse);
    expect(sushiIsEnglishLanguage(null), isFalse);
  });
}
