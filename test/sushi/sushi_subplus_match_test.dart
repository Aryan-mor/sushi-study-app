import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/sushi/subtitles/sushi_subplus.dart';

void main() {
  group('parseSeasonEpisode', () {
    final cases = <String, ({int? s, int? e})>{
      'Euphoria.US.S03E08.1080p.WEB.h264-ETHEL': (s: 3, e: 8),
      'euphoria.us.s01e07.720p.web.h264-tbs': (s: 1, e: 7),
      'Euphoria - S03E01 - Try to Get with Me.srt': (s: 3, e: 1),
      'Euphoria - Season 3 (2019)': (s: 3, e: null),
      'Euphoria.US.Season.01.COMPLETE.WEB-DL.480p.x264.PSA': (s: 1, e: null),
      'Euphoria - First Season (2019)': (s: 1, e: null),
      'Breaking Bad - Third Season (2010)': (s: 3, e: null),
      'The Wire 3x11.srt': (s: 3, e: 11),
      'Show.Name.Episode.4.srt': (s: null, e: 4),
      'قسمت ۱۲': (s: null, e: null), // Persian digits not handled yet — episode-only ASCII path
      'Some.Movie.2021.1080p.BluRay.x264': (s: null, e: null),
    };
    cases.forEach((input, want) {
      test(input, () {
        final got = parseSeasonEpisode(input);
        expect(got.season, want.s, reason: 'season');
        expect(got.episode, want.e, reason: 'episode');
      });
    });
  });

  SubplusSubFile f(String name) => SubplusSubFile(name: name, ext: '.srt', text: '1\n00:00:01,000 --> 00:00:02,000\nx\n');

  group('pickEpisodeFile', () {
    test('exact S/E match wins in a season pack', () {
      final files = [
        f('Euphoria.S03E01.1080p.srt'),
        f('Euphoria.S03E02.1080p.srt'),
        f('Euphoria.S03E03.1080p.srt'),
      ];
      expect(pickEpisodeFile(files, 3, 2)!.name, 'Euphoria.S03E02.1080p.srt');
    });

    test('falls back to episode-only match when season absent from names', () {
      final files = [f('Episode 01.srt'), f('Episode 02.srt')];
      expect(pickEpisodeFile(files, 3, 2)!.name, 'Episode 02.srt');
    });

    test('single file is returned as-is', () {
      expect(pickEpisodeFile([f('whatever.srt')], 9, 9)!.name, 'whatever.srt');
    });

    test('no match -> null', () {
      final files = [f('Euphoria.S01E01.srt'), f('Euphoria.S01E02.srt')];
      expect(pickEpisodeFile(files, 3, 5), isNull);
    });
  });

  group('seasonMatchScore', () {
    SubplusPack pack(String title, List<String> releases) => SubplusPack(
          tag: 't',
          title: title,
          imdb: '',
          year: '2019',
          series: true,
          translator: '',
          releases: releases,
          poster: '',
        );

    test('matching season -> +1', () {
      expect(seasonMatchScore(pack('Euphoria - Season 3 (2019)', const []), 3), 1);
    });
    test('wrong season -> -1', () {
      expect(seasonMatchScore(pack('Euphoria - First Season (2019)', const []), 3), -1);
    });
    test('unknown season -> 0', () {
      expect(seasonMatchScore(pack('Euphoria Farsi Subtitle', const []), 3), 0);
    });
    test('season found in a release line even if not the title', () {
      expect(seasonMatchScore(pack('Euphoria', const ['Euphoria.US.S03E01.1080p.WEB']), 3), 1);
    });
  });

  group('sushiFilterSubplusPacks', () {
    SubplusPack movie({
      required String title,
      required String year,
      bool series = false,
    }) =>
        SubplusPack(
          tag: title,
          title: title,
          imdb: '',
          year: year,
          series: series,
          translator: '',
          releases: const ['x'],
          poster: '',
        );

    test('same title different year is dropped when playing year is known', () {
      final packs = [
        movie(title: 'The Breadwinner (2017)', year: '2017'),
        movie(title: 'The Box Man (2024)', year: '2024'),
      ];
      expect(
        sushiFilterSubplusPacks(packs, query: 'The Breadwinner', year: '2026'),
        isEmpty,
      );
    });

    test('keeps the pack whose year matches the playing movie', () {
      final packs = [
        movie(title: 'The Breadwinner (2017)', year: '2017'),
        movie(title: 'The Breadwinner (2026)', year: '2026'),
      ];
      final got = sushiFilterSubplusPacks(packs, query: 'The Breadwinner', year: '2026');
      expect(got, hasLength(1));
      expect(got.single.year, '2026');
    });

    test('movies drop series packs', () {
      final packs = [
        movie(title: 'The Breadwinner (2017)', year: '2017'),
        movie(title: 'The Residence - Season 1 (2025)', year: '2025', series: true),
      ];
      final got = sushiFilterSubplusPacks(packs, query: 'The Breadwinner');
      expect(got, hasLength(1));
      expect(got.single.title, 'The Breadwinner (2017)');
    });

    test('drops a named other-episode pack in the same season', () {
      SubplusPack pack(String title) => SubplusPack(
            tag: title,
            title: title,
            imdb: '',
            year: '1994',
            series: true,
            translator: '',
            releases: const [],
            poster: '',
          );
      final got = sushiFilterSubplusPacks(
        [
          pack('friends s03 e12 UNCUT.DVDRip.XviD'),
          pack('Friends Season 3 Complete'),
          pack('friends.s03e13.720p.web'),
        ],
        episode: (season: 3, episode: 13),
      );
      expect(got.map((p) => p.title), [
        'Friends Season 3 Complete',
        'friends.s03e13.720p.web',
      ]);
    });
  });

  group('pickMovieSubFile', () {
    test('skips SDH when a dialogue track exists', () {
      final files = [
        f('The.Breadwinner.2026.en[sdh].srt'),
        f('The.Breadwinner.2026.en.srt'),
      ];
      expect(pickMovieSubFile(files)!.name, 'The.Breadwinner.2026.en.srt');
    });

    test('falls back to SDH when that is the only file', () {
      expect(
        pickMovieSubFile([f('The.Breadwinner.2026.en[sdh].srt')])!.name,
        'The.Breadwinner.2026.en[sdh].srt',
      );
    });
  });

  group('sushiSubtitleSourceMatchScore', () {
    SubplusPack pack(String title) => SubplusPack(
          tag: 't',
          title: title,
          imdb: '',
          year: '',
          series: true,
          translator: '',
          releases: [title],
          poster: '',
        );

    test('DVDRip/XviD loses to 720p WEB on a 720p file', () {
      final dvd = pack('friends s03 e12 UNCUT.DVDRip.XviD');
      final web = pack('Friends.S03E12.720p.WEB');
      expect(sushiSubtitleSourceMatchScore(dvd, '720p'), lessThan(sushiSubtitleSourceMatchScore(web, '720p')));
    });
  });
}
