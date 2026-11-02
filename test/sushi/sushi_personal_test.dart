import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/sushi/personal/sushi_personal.dart';
import 'package:fladder/sushi/personal/sushi_personal_transport.dart';
import 'package:fladder/sushi/sushi_playback_model.dart';
import 'package:fladder/sushi/sushi_list_pb.dart';
import 'package:fladder/sushi/sushi_list_transport.dart';
import 'package:fladder/sushi/sushi_play_pb.dart';
import 'package:fladder/sushi/sushi_sync_pb.dart';

/// Golden bytes are the server's own Go protobuf types marshalled deterministically (ADR 0037
/// wire: PlayReq.personal_id = 4, AckReq.personal_id = 3, ProgEvent.personal_id = 5,
/// ListScope.MY_VIDEOS = 10, ListRes.personal_videos = 5, WatchedState.personal_id = 3).
Uint8List _hex(String s) =>
    Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

String _toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('personal video wire (ADR 0037)', () {
    test('PlayReq carries personal_id, never file_id', () {
      expect(_toHex(sushiEncodePlayReq(fileId: 0, personalId: 42)), '1801202a');
      expect(_toHex(sushiEncodePlayReq(fileId: 0, personalId: 300, force: true)), '1001180120ac02');
    });

    test('AckReq carries personal_id', () {
      expect(_toHex(sushiEncodeAckReq(fileId: 0, messageId: 77, personalId: 42)), '104d182a');
    });

    test('ListReq asks for MY_VIDEOS', () {
      expect(_toHex(sushiEncodeListReq(scope: SushiListScope.myVideos, sort: SushiListSort.unspecified, cursor: 50)),
          '080a3832');
    });

    test('ListRes decodes personal_videos', () {
      final res = SushiListRes.decode(
        _hex('10322a17082a1208d8aad988d984d8af188d1d208080808020281e2a0a082b1204547269703001'),
      );
      expect(res.cursor, 50);
      expect(res.rows, isEmpty);
      expect(res.personalVideos, hasLength(2));
      final first = res.personalVideos[0];
      expect(first.personalId, 42);
      expect(first.title, 'تولد');
      expect(first.durationS, 3725);
      expect(first.sizeBytes, 1 << 33);
      expect(first.positionS, 30);
      expect(first.done, isFalse);
      expect(res.personalVideos[1].title, 'Trip');
      expect(res.personalVideos[1].done, isTrue);
    });

    test('ProgEvent for a personal video carries personal_id and no episode_id', () {
      expect(_toHex(sushiEncodeProgEvent(episodeId: 0, positionS: 60, durationS: 120, personalId: 42)),
          '103c2078282a');
    });

    test('ProgEvent for a catalog episode is unchanged', () {
      expect(_toHex(sushiEncodeProgEvent(episodeId: 7, positionS: 60, fileId: 3, durationS: 120)), '0807103c18032078');
    });

    test('Sync drops personal rows instead of storing them as episode 0', () {
      final res = SushiSyncRes.decode(_hex('0a04080710010a041001182a1009'));
      expect(res.watched.map((w) => w.episodeId), [7]);
      expect(res.watchedWatermark, 9);
    });

    test('PersonalReq carries the id and the action (ADR 0038)', () {
      // sushi.v1.PersonalReq{personal_id: 42, action: DELETE|SHARE}, marshalled by Go.
      expect(_toHex(sushiEncodePersonalReq(personalId: 42, action: SushiPersonalAction.delete)), '082a1002');
      expect(_toHex(sushiEncodePersonalReq(personalId: 42, action: SushiPersonalAction.share)), '082a1001');
    });

    test('locators keep personal and catalog waiters apart', () {
      expect(sushiLocatorForPersonal(42), 'plp_42');
      expect(sushiLocatorForFile(42), 'plm_42');
    });
  });

  group('personal playback subtitles are the file\'s own', () {
    test('only Off until the player lists the muxed tracks, and the player knows it is personal', () {
      final item = sushiPersonalVideoToItem(const SushiPersonalVideo(personalId: 42, title: 'Trip'));
      final personal = SushiPlaybackModel(item: item, media: const Media(url: 'x'), personalId: 42);
      expect(personal.subStreams, hasLength(1));
      expect(personal.subStreams.single.index, -1);
      expect(sushiIsPersonalPlayback(personal), isTrue);

      final film = SushiPlaybackModel(item: item, media: const Media(url: 'x'));
      expect(sushiIsPersonalPlayback(film), isFalse);
      expect(sushiIsPersonalPlayback(null), isFalse);
    });

    test('muxed tracks follow Off and survive copyWith', () {
      final item = sushiPersonalVideoToItem(const SushiPersonalVideo(personalId: 42, title: 'Trip'));
      final muxed = SubStreamModel(
        name: 'English',
        id: '3',
        title: 'English',
        displayTitle: 'English · EN',
        language: 'en',
        codec: 'subrip',
        isDefault: false,
        isExternal: false,
        index: 1,
      );
      final personal = SushiPlaybackModel(item: item, media: const Media(url: 'x'), personalId: 42)
          .copyWith(embeddedSubs: [muxed]);
      expect(personal.subStreams.map((s) => s.index), [-1, 1]);
      expect(personal.copyWith(episodeId: 0).subStreams.last.id, '3');
    });
  });

  group('personal item mapping', () {
    test('item id round-trips and never parses as anything else', () {
      expect(sushiPersonalIdFromItemId(sushiPersonalItemId(42)), 42);
      expect(sushiPersonalIdFromItemId('sushi_tmdb_42'), isNull);
    });

    test('a started video carries its resume point', () {
      final item = sushiPersonalVideoToItem(
        const SushiPersonalVideo(personalId: 42, title: 'Trip', durationS: 200, positionS: 50),
      );
      expect(item.name, 'Trip');
      expect(item.userData.playbackPositionTicks, 50 * 10000000);
      expect(item.userData.progress, closeTo(25, 0.01));
      expect(item.userData.played, isFalse);
    });

    test('a watched video starts over', () {
      final item = sushiPersonalVideoToItem(
        const SushiPersonalVideo(personalId: 42, title: 'Trip', durationS: 200, positionS: 190, done: true),
      );
      expect(item.userData.played, isTrue);
      expect(item.userData.playbackPositionTicks, 0);
    });
  });
}
