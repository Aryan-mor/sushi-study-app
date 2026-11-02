import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/sushi/sushi_account_playback_pref.dart';
import 'package:fladder/sushi/sushi_media_variant.dart';
import 'package:flutter_test/flutter_test.dart';

VersionStreamModel _stream({
  required int index,
  required String name,
  int height = 1080,
  bool hasSubs = false,
  List<SubStreamModel> subStreams = const [],
  String displayName = '',
}) {
  return VersionStreamModel(
    name: name,
    displayName: displayName,
    index: index,
    id: 'ms_$index',
    defaultAudioStreamIndex: 1,
    defaultSubStreamIndex: hasSubs || subStreams.isNotEmpty ? 2 : -1,
    videoStreams: [
      VideoStreamModel(
        name: '',
        codec: 'h264',
        isDefault: true,
        isExternal: false,
        index: 0,
        videoDoViTitle: null,
        videoRangeType: null,
        bitRate: null,
        width: height == 1080 ? 1920 : 1280,
        height: height,
        frameRate: 24,
      ),
    ],
    audioStreams: const [],
    subStreams: subStreams,
  );
}

void main() {
  group('sushiPickVersionStreamIndex cold default', () {
    test('prefers 1080 soft sub', () {
      final streams = [
        _stream(index: 0, name: '720p Dub Persian', height: 720),
        _stream(index: 1, name: '1080p Dub Persian', height: 1080),
        _stream(index: 2, name: '1080p SoftSub Persian', height: 1080, hasSubs: true),
      ];
      expect(
        sushiPickVersionStreamIndex(streams, SushiMediaVariantPreference.unset),
        2,
      );
    });

    test('falls back to first 1080 when no soft sub', () {
      final streams = [
        _stream(index: 0, name: '720p English', height: 720),
        _stream(index: 1, name: '1080p English', height: 1080),
      ];
      expect(
        sushiPickVersionStreamIndex(streams, SushiMediaVariantPreference.unset),
        1,
      );
    });

    test('falls back to 720 tier when no 1080', () {
      final streams = [
        _stream(index: 0, name: '480p English', height: 480),
        _stream(index: 1, name: '720p SoftSub Persian', height: 720, hasSubs: true),
      ];
      expect(
        sushiPickVersionStreamIndex(streams, SushiMediaVariantPreference.unset),
        1,
      );
    });
  });

  group('sushiPickVersionStreamIndex user preference', () {
    test('remembers 720 quality', () {
      final streams = [
        _stream(index: 0, name: '1080p SoftSub Persian', height: 1080, hasSubs: true),
        _stream(index: 1, name: '720p SoftSub Persian', height: 720, hasSubs: true),
      ];
      const pref = SushiMediaVariantPreference(qualityHeight: 720);
      expect(sushiPickVersionStreamIndex(streams, pref), 1);
    });

    test('remembers dubbed with fallback to soft sub at same tier', () {
      final streams = [
        _stream(index: 0, name: '1080p SoftSub Persian', height: 1080, hasSubs: true),
        _stream(index: 1, name: '720p Dub Persian', height: 720),
      ];
      const pref = SushiMediaVariantPreference(
        qualityHeight: 1080,
        delivery: SushiStreamDelivery.dubbed,
      );
      expect(sushiPickVersionStreamIndex(streams, pref), 0);
    });

    test('carries dubbed preference to lower tier when preferred tier has no match', () {
      final streams = [
        _stream(index: 0, name: '720p Dub Persian', height: 720),
        _stream(index: 1, name: '1080p English', height: 1080),
      ];
      const pref = SushiMediaVariantPreference(
        qualityHeight: 1080,
        delivery: SushiStreamDelivery.dubbed,
      );
      expect(sushiPickVersionStreamIndex(streams, pref), 0);
    });
  });

  group('sushiClassifyVersionStream', () {
    test('detects dubbed from label', () {
      final meta = sushiClassifyVersionStream(_stream(index: 0, name: '1080p Dub Persian'));
      expect(meta.delivery, SushiStreamDelivery.dubbed);
      expect(meta.qualityHeight, 1080);
    });

    test('detects duble scene token as dubbed', () {
      final meta = sushiClassifyVersionStream(_stream(
        index: 0,
        name: 'Spider.Man.Brand.New.Day.2026.720p.Hdrip.Duble.MyMoviz.mp4',
        height: 720,
      ));
      expect(meta.delivery, SushiStreamDelivery.dubbed);
      expect(meta.qualityHeight, 720);
    });

    test('چسبیده without a muxed track is not hardsub on the picker', () {
      final meta = sushiClassifyVersionStream(_stream(
        index: 0,
        name: '720p زیرنویس_فارسی_چسبیده',
        height: 720,
      ));
      expect(meta.delivery, isNot(SushiStreamDelivery.hardSub));
    });

    test('HDTS filename is hardsub on the picker', () {
      final meta = sushiClassifyVersionStream(_stream(
        index: 0,
        name: 'Spider_Man_Brand_New_Day_2026_720P_Hdts_MyMoviz_video_converter.mp4',
        height: 720,
      ));
      expect(meta.delivery, SushiStreamDelivery.hardSub);
    });

    test('catalog sub_langs make چسبیده a soft sub', () {
      final meta = sushiClassifyVersionStream(_stream(
        index: 0,
        name: '720p HDTS',
        height: 720,
        subStreams: [
          SubStreamModel(
            name: 'FA',
            id: 'sub0',
            title: 'FA',
            displayTitle: 'FA',
            language: 'fa',
            codec: '',
            isDefault: true,
            isExternal: false,
            index: 0,
          ),
        ],
      ));
      expect(meta.delivery, SushiStreamDelivery.softSub);
    });

    test('extracts resolution from an underscore-delimited raw filename', () {
      final meta = sushiClassifyVersionStream(_stream(
        index: 0,
        name: 'One_Night_Only_2026_1080p_10bit_WEB_DL_6CH_x265_SoftSub_DigiMovi.mkv',
      ));
      expect(meta.qualityHeight, 1080);
      expect(meta.delivery, SushiStreamDelivery.softSub);
    });
  });

  group('sushiFindVersionStreamIndexForPreference', () {
    test('returns null with no preference set', () {
      final streams = [
        _stream(index: 0, name: '1080p SoftSub Persian', height: 1080, hasSubs: true),
        _stream(index: 1, name: '720p SoftSub Persian', height: 720, hasSubs: true),
      ];
      expect(
        sushiFindVersionStreamIndexForPreference(streams, SushiMediaVariantPreference.unset),
        isNull,
      );
    });

    test('returns null with fewer than two versions even if a preference is set', () {
      final streams = [_stream(index: 0, name: '1080p SoftSub Persian', height: 1080, hasSubs: true)];
      const pref = SushiMediaVariantPreference(qualityHeight: 720);
      expect(sushiFindVersionStreamIndexForPreference(streams, pref), isNull);
    });

    test('finds the matching index when a preference matches', () {
      final streams = [
        _stream(index: 0, name: '1080p SoftSub Persian', height: 1080, hasSubs: true),
        _stream(index: 1, name: '720p SoftSub Persian', height: 720, hasSubs: true),
      ];
      const pref = SushiMediaVariantPreference(qualityHeight: 720);
      expect(sushiFindVersionStreamIndexForPreference(streams, pref), 1);
    });
  });

  group('account playback pref (onboarding answer)', () {
    const subs = SushiAccountPlaybackPref(audio: SushiAudioPref.original);
    const dub = SushiAccountPlaybackPref(audio: SushiAudioPref.dub);

    // Regression: Recep Ivedik 6 opened on the dubbed file for a user who told the bot they
    // prefer subtitles -- the cold pick never looked at the answer.
    test('prefers subtitles over a dub listed first', () {
      final streams = [
        _stream(index: 0, name: '720p Dub', height: 720),
        _stream(index: 1, name: '1080p Dub', height: 1080),
        _stream(index: 2, name: '720p HardSub', height: 720),
        _stream(index: 3, name: '1080p HardSub', height: 1080),
      ];
      expect(sushiPickColdVersionStreamIndex(streams, account: subs), 3);
      expect(sushiPickVersionStreamIndex(streams, SushiMediaVariantPreference.unset, account: subs), 3);
    });

    test('a subtitled lower quality beats a dubbed higher one', () {
      final streams = [
        _stream(index: 0, name: '1080p Dub', height: 1080),
        _stream(index: 1, name: '720p SoftSub', height: 720, hasSubs: true),
      ];
      expect(sushiPickColdVersionStreamIndex(streams, account: subs), 1);
    });

    test('original audio (unlabelled) beats a dub for a subtitles user', () {
      final streams = [
        _stream(index: 0, name: '1080p Dub', height: 1080),
        _stream(index: 1, name: '1080p', height: 1080),
      ];
      expect(sushiPickColdVersionStreamIndex(streams, account: subs), 1);
    });

    test('dub users get the dub', () {
      final streams = [
        _stream(index: 0, name: '1080p SoftSub', height: 1080, hasSubs: true),
        _stream(index: 1, name: '1080p Dub', height: 1080),
      ];
      expect(sushiPickColdVersionStreamIndex(streams, account: dub), 1);
    });

    test('dub label wins even when the file also has catalog sub tracks', () {
      final streams = [
        _stream(index: 0, name: '1080p SoftSub', height: 1080, hasSubs: true),
        _stream(
          index: 1,
          name: '1080p Dub Persian',
          height: 1080,
          subStreams: [
            SubStreamModel(
              name: 'FA',
              id: 's1',
              title: 'FA',
              displayTitle: 'FA',
              language: 'fa',
              codec: '',
              isDefault: true,
              isExternal: false,
              index: 0,
            ),
          ],
        ),
      ];
      expect(sushiPickColdVersionStreamIndex(streams, account: dub), 1);
    });

    test('max height caps the pick, closest below wins', () {
      const capped = SushiAccountPlaybackPref(audio: SushiAudioPref.original, maxHeight: 720);
      final streams = [
        _stream(index: 0, name: '1080p SoftSub', height: 1080, hasSubs: true),
        _stream(index: 1, name: '480p SoftSub', height: 480, hasSubs: true),
        _stream(index: 2, name: '720p SoftSub', height: 720, hasSubs: true),
      ];
      expect(sushiPickColdVersionStreamIndex(streams, account: capped), 2);
    });

    test('a custom file name beats a taller automatic pick', () {
      final streams = [
        _stream(index: 0, name: '1080p SoftSub', height: 1080, hasSubs: true),
        _stream(index: 1, name: '720p WEB-DL', height: 720, displayName: '1080 soren soft sub'),
      ];
      expect(sushiPickColdVersionStreamIndex(streams), 1);
    });

    test('an explicit per-title pick still wins over a custom file name', () {
      final streams = [
        _stream(index: 0, name: '1080p SoftSub', height: 1080, hasSubs: true),
        _stream(index: 1, name: '720p WEB-DL', height: 720, displayName: '1080 soren soft sub'),
      ];
      const pref = SushiMediaVariantPreference(qualityHeight: 1080, delivery: SushiStreamDelivery.softSub);
      expect(sushiPickVersionStreamIndex(streams, pref), 0);
    });

    test('an explicit per-title pick still wins over the account answer', () {
      final streams = [
        _stream(index: 0, name: '1080p SoftSub', height: 1080, hasSubs: true),
        _stream(index: 1, name: '1080p Dub', height: 1080),
      ];
      const pref = SushiMediaVariantPreference(qualityHeight: 1080, delivery: SushiStreamDelivery.dubbed);
      expect(sushiPickVersionStreamIndex(streams, pref, account: subs), 1);
    });

    test('persian with subtitles prefers hard sub over soft sub', () {
      const faOn = SushiAccountPlaybackPref(
        audio: SushiAudioPref.original,
        maxHeight: 1080,
        subtitleLang: 'fa',
        subs: SushiSubsPref.on,
      );
      final streams = [
        _stream(index: 0, name: '1080p SoftSub', height: 1080, hasSubs: true),
        _stream(index: 1, name: '1080p HardSub', height: 1080),
        _stream(index: 2, name: '1080p Dub', height: 1080),
      ];
      expect(sushiPickColdVersionStreamIndex(streams, account: faOn), 1);
    });

    test('without subtitles does not default to a hard sub', () {
      const faOff = SushiAccountPlaybackPref(
        audio: SushiAudioPref.original,
        maxHeight: 1080,
        subtitleLang: 'fa',
        subs: SushiSubsPref.off,
      );
      final streams = [
        _stream(index: 0, name: '1080p HardSub', height: 1080),
        _stream(index: 1, name: '1080p SoftSub', height: 1080, hasSubs: true),
      ];
      expect(sushiPickColdVersionStreamIndex(streams, account: faOff), 1);
    });

    test('fromWire maps the server strings', () {
      expect(
        SushiAccountPlaybackPref.fromWire('original', 1080, 'fa'),
        const SushiAccountPlaybackPref(
          audio: SushiAudioPref.original,
          maxHeight: 1080,
          subtitleLang: 'fa',
        ),
      );
      expect(SushiAccountPlaybackPref.fromWire('', 0).isUnset, isTrue);
      expect(SushiAccountPlaybackPref.fromWire('bogus', -5).isUnset, isTrue);
    });
  });
}
