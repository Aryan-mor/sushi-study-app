import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/sushi/sushi_playback_audio.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_playback_model.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

void main() {
  SushiPlaybackModel modelFor(MediaStreamsModel streams) {
    final item = sushiRowToItemBaseModel(
      const SushiRow(
        tmdbId: 1,
        kind: SushiKind.movie,
        title: 'x',
        year: 2020,
        rating: 1,
        poster: 'p',
      ),
    ) as MovieModel;
    return SushiPlaybackModel(
      item: item,
      media: const Media(url: 'http://127.0.0.1/1'),
      mediaStreams: streams,
    );
  }

  test('empty langs resolve to default muxed audio', () {
    final streams = sushiBuildMediaStreams(const [
      SushiFile(
        fileId: 1,
        qualityLabel: '1080p',
        height: 1080,
        audioLangs: '',
        subLangs: '',
        sizeBytes: 1,
        durationS: 1,
        state: SushiFileState.ready,
      ),
    ]);
    final model = modelFor(streams);
    expect(sushiResolvePlaybackAudioStream(model)?.index, 0);
    expect(sushiDefaultAudioTrackIndex(model), 0);
    expect(sushiShouldSkipAudioTrackOff(model), isTrue);
  });

  test('native default audio index never negative for Off-only catalog', () {
    final streams = MediaStreamsModel(
      versionStreamIndex: 0,
      defaultAudioStreamIndex: -1,
      versionStreams: [
        VersionStreamModel(
          name: '1080p',
          index: 0,
          id: 'sushi_file_1',
          defaultAudioStreamIndex: -1,
          defaultSubStreamIndex: -1,
          videoStreams: const [],
          audioStreams: [AudioStreamModel.no()],
          subStreams: const [],
        ),
      ],
    );
    final model = modelFor(streams);
    expect(sushiResolvePlaybackAudioStream(model), isNull);
    expect(sushiDefaultAudioTrackIndex(model), 1);
  });
}
