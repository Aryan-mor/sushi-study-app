import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_sync_dto.dart';

void main() {
  test('offline filename round-trips the Sushi file id', () {
    expect(sushiOfflineFileName(4211), 'sushi_file_4211.mkv');
    expect(sushiFileIdFromOfflineName('sushi_file_4211.mkv'), 4211);
    expect(sushiFileIdFromOfflineName('other.mkv'), isNull);
  });

  test('pick ready file prefers the selected version stream', () {
    const files = [
      SushiFile(
        fileId: 1,
        qualityLabel: '720p',
        height: 720,
        audioLangs: 'en',
        subLangs: '',
        sizeBytes: 10,
        durationS: 1,
        state: SushiFileState.ready,
      ),
      SushiFile(
        fileId: 2,
        qualityLabel: '1080p',
        height: 1080,
        audioLangs: 'en',
        subLangs: '',
        sizeBytes: 20,
        durationS: 1,
        state: SushiFileState.ready,
      ),
      SushiFile(
        fileId: 3,
        qualityLabel: 'pending',
        height: 0,
        audioLangs: '',
        subLangs: '',
        sizeBytes: 0,
        durationS: 0,
        state: SushiFileState.pending,
      ),
    ];
    expect(sushiPickReadyFile(files)?.fileId, 1);
    expect(sushiPickReadyFile(files, versionStreamId: 'sushi_file_2')?.fileId, 2);
  });

  test('movie DTO keeps Fladder sync layout fields', () {
    final movie = sushiRowToItemBaseModel(
      const SushiRow(
        tmdbId: 550,
        kind: SushiKind.movie,
        title: 'Fight Club',
        year: 1999,
        rating: 84,
        poster: 'fc',
      ),
    ) as MovieModel;
    const file = SushiFile(
      fileId: 99,
      qualityLabel: '1080p',
      height: 1080,
      audioLangs: 'en',
      subLangs: 'fa',
      sizeBytes: 123456,
      durationS: 139,
      state: SushiFileState.ready,
    );
    final dto = sushiItemToBaseItemDto(movie, file: file);
    expect(dto.id, movie.id);
    expect(dto.type, BaseItemKind.movie);
    expect(dto.canDownload, isTrue);
    expect(dto.path, 'sushi_file_99.mkv');
    expect(dto.mediaSources, isNotNull);
    expect(dto.mediaSources!.first.size, 123456);
    expect(dto.mediaSources!.first.id, 'sushi_file_99');
    expect(sushiFileIdFromOfflineName(dto.path), 99);
  });

  test('rejects fake Jellyfin host from sushi://local', () {
    expect(
      sushiImageUrlAllowed(
        'http://sushi/local/Items/sushi_tmdb_220102/Images/Logo?fillHeight=500&fillWidth=500&quality=90',
      ),
      isFalse,
    );
    expect(sushiImageUrlAllowed('https://image.tmdb.org/t/p/w500/abc.jpg'), isTrue);
    expect(sushiImageUrlAllowed('sushi://local/Items/x/Images/Primary'), isFalse);
  });
}
