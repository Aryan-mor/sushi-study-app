import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/sushi/sushi_variant_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

VersionStreamModel _stream({
  required String name,
  int height = 1080,
  bool hasSubs = false,
  String language = 'eng',
  int? sizeBytes,
}) {
  return VersionStreamModel(
    name: name,
    sizeBytes: sizeBytes,
    index: 0,
    id: 'ms_0',
    defaultAudioStreamIndex: 1,
    defaultSubStreamIndex: hasSubs ? 2 : -1,
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
        width: height >= 1080 ? 1920 : 1280,
        height: height,
        frameRate: 24,
      ),
    ],
    audioStreams: [
      AudioStreamModel(
        displayTitle: language == 'fa' ? 'Persian' : 'English',
        name: '',
        codec: 'aac',
        isDefault: true,
        isExternal: false,
        index: 1,
        language: language,
        channelLayout: 'stereo',
        sampleRate: 48000,
        channels: 2,
        bitRate: null,
        bitDepth: null,
        profile: null,
        spatialFormat: null,
      ),
    ],
    subStreams: hasSubs
        ? [
            SubStreamModel(
              id: 'sub_0',
              title: 'Persian',
              displayTitle: 'Persian',
              name: '',
              codec: 'subrip',
              isDefault: false,
              isExternal: false,
              index: 2,
              language: 'fa',
            ),
          ]
        : const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppLocalizations> loadEn() => Future.value(lookupAppLocalizations(const Locale('en')));
  Future<AppLocalizations> loadFa() => Future.value(lookupAppLocalizations(const Locale('fa')));

  test('formats original english bluray in english locale', () async {
    final l10n = await loadEn();
    final label = sushiLocalizedVersionStreamLabel(
      l10n,
      _stream(name: '1080p - English - BluRay'),
    );
    expect(label, '1080p - English - BluRay');
  });

  test('formats dubbed persian in persian locale', () async {
    final l10n = await loadFa();
    final label = sushiLocalizedVersionStreamLabel(
      l10n,
      _stream(
        name: '1080p - dubbed (Persian) - WEB-DL',
        language: 'fa',
      ),
    );
    expect(label, '1080p - دوبله (فارسی) - WEB-DL');
  });

  test('formats soft sub without language suffix', () async {
    final l10n = await loadEn();
    final label = sushiVersionStreamLabel(
      _stream(name: '720p - soft sub - PSA x264 - 302 MB', height: 720, hasSubs: true),
      l10n: l10n,
    );
    expect(label, '720p - soft sub - PSA x264 - 302 MB');
  });

  test('localizes server soft sub webdl label in persian locale', () async {
    final l10n = await loadFa();
    final label = sushiVersionStreamLabel(
      _stream(
        name: '1080p - soft sub - 10Bit WEB-DL x265 - 500 MB',
        hasSubs: true,
      ),
      l10n: l10n,
    );
    expect(label, '1080p - ${l10n.sushiVariantSoftSub} - 10Bit WEB-DL x265 - 500 MB');
  });

  test('composes a clean label from a raw release filename', () async {
    final l10n = await loadEn();
    final label = sushiVersionStreamLabel(
      _stream(
        name: 'One_Night_Only_2026_1080p_10bit_WEB_DL_6CH_x265_SoftSub_DigiMovi.mkv',
        hasSubs: true,
      ),
      l10n: l10n,
    );
    expect(label, '1080p x265 10bit ${l10n.sushiVariantSoftSub}');
  });

  test('a plain single-segment server label is not treated as a raw filename', () async {
    final l10n = await loadEn();
    final label = sushiVersionStreamLabel(
      _stream(name: 'Original', hasSubs: false),
      l10n: l10n,
    );
    expect(label, 'Original');
  });

  // Regression: six versions of Recep Ivedik 6 all read "@exampleFilmChannel [ Recep ivedik 6 2019 ].mp4".
  test('identical labels get their file size', () async {
    final l10n = await loadEn();
    const raw = '@exampleFilmChannel [ Recep ivedik 6 2019 ].mp4';
    final a = _stream(name: raw, height: 0, sizeBytes: 800 * 1024 * 1024);
    final b = _stream(name: raw, height: 0, sizeBytes: 1455 * 1024 * 1024);
    expect(sushiVersionStreamLabel(a, l10n: l10n, siblings: [a, b]), '$raw · 800 MB');
    expect(sushiVersionStreamLabel(b, l10n: l10n, siblings: [a, b]), '$raw · 1.4 GB');
  });

  test('distinct labels stay without a size', () async {
    final l10n = await loadEn();
    final a = _stream(name: '720p', height: 720, sizeBytes: 800 * 1024 * 1024);
    final b = _stream(name: '1080p', sizeBytes: 1800 * 1024 * 1024);
    expect(sushiVersionStreamLabel(a, l10n: l10n, siblings: [a, b]), '720p');
  });

  test('custom file name wins over the release label', () {
    final stream = _stream(name: '1080p WEB-DL SoftSub');
    final named = VersionStreamModel(
      name: stream.name,
      displayName: '1080 soren soft sub',
      index: stream.index,
      id: stream.id,
      defaultAudioStreamIndex: stream.defaultAudioStreamIndex,
      defaultSubStreamIndex: stream.defaultSubStreamIndex,
      videoStreams: stream.videoStreams,
      audioStreams: stream.audioStreams,
      subStreams: stream.subStreams,
    );
    expect(sushiVersionStreamLabel(named), '1080 soren soft sub');
  });

  test('localizes the delivery token of a compact server label', () async {
    final l10n = await loadFa();
    expect(sushiVersionStreamLabel(_stream(name: '720p Dub', height: 720), l10n: l10n), '720p دوبله');
    expect(
      sushiVersionStreamLabel(_stream(name: '1080p x265 HardSub'), l10n: l10n),
      '1080p x265 زیرنویس چسبیده',
    );
  });
}
