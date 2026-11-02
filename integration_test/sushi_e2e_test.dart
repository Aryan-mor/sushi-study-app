// Sushi playback E2E — drives the REAL app (real Telegram session, real API/delivery bots, real
// mpv/native playback) on whatever already-logged-in device `flutter test integration_test/... -d
// <device>` targets. Same philosophy as sushi_playback_e2e_test.dart: call the same
// provider/extension entry points the real UI buttons call (`MovieDetails.fetchDetails`,
// `ItemBaseModel.play`, `videoPlayerProvider.stateStream`) instead of tapping through
// layout/locale-fragile widgets.
//
// This suite exists specifically to catch the two classes of bug found live this session:
//   - the native gomobile bridge crashing the whole process (`fatal error: bulkBarrierPreWrite:
//     unaligned arguments`) when two calls into it overlap — most recently stopPlaybackSession's
//     cleanup racing an unrelated Sushi protocol call. The play/close stress phase below
//     reproduces exactly that shape (play, then immediately back out, repeatedly).
//   - the client over-requesting the assigned API bot — a home refresh, an item open, or a
//     pull-to-refresh sending far more wire calls than the one or two each should ever need, and
//     the reported bug where a refresh left the detail screen with neither a Play button nor its
//     info. sushiRequestCount (sushi_bridge_queue.dart) is incremented on every single wire call
//     app-wide, so it's a reliable place to catch a request-count regression without new logging.
//
// Requires a device that is already logged in (Telegram + Sushi /initbot already completed) — this
// is a dev/QA tool, not a from-scratch CI suite.
//
// Run:
//   flutter test integration_test/sushi_e2e_test.dart -d <device-id>

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fladder/main.dart' as app;
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/sushi/sushi_media_streams.dart';
import 'package:fladder/providers/items/movies_details_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/sushi/providers/sushi_home_rails_provider.dart';
import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/util/item_base_model/play_item_helpers.dart';
import 'package:fladder/wrappers/players/player_states.dart';

/// Generous enough for /item [+ /files] on an open, or a single /home refresh — tight enough to
/// fail loudly if a regression reintroduces per-interaction request spam.
const _maxRequestsPerInteraction = 4;
const _railsTimeout = Duration(seconds: 20);
const _detailsTimeout = Duration(seconds: 20);
// Generous: the native player opens a separate Android Activity (VideoPlayerActivity), and its
// cold-start (decoder init, first delivery byte) can run well past what a warm in-engine player
// backend would need — confirmed live that actual playback starts well under this on a warm app.
const _playTimeout = Duration(seconds: 45);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Sushi e2e (home -> open -> play -> close -> refresh, request-count guarded)',
      (tester) async {
    app.main(const <String>[]);
    // Cold boot: TDLib restore, /initbot handshake, first home rails fetch.
    await tester.pumpAndSettle(const Duration(seconds: 8));

    final refElement = tester.element(find.byType(app.Main));
    final ref = refElement as WidgetRef;
    final BuildContext context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context, listen: false);

    final results = <String, String>{};
    void record(String label, bool pass, String detail) {
      final line = '${pass ? 'PASS' : 'FAIL'} — $detail';
      results[label] = line;
      // ignore: avoid_print
      print('[sushi-e2e] $label: $line');
    }

    Stream<PlayerState> playerStates() => ref.read(videoPlayerProvider).stateStream;

    // ---------------------------------------------------------------------
    // 1) Cold-start home rails populate, without hammering the API bot.
    // ---------------------------------------------------------------------
    sushiResetRequestCounter();
    ItemBaseModel? firstItem;
    try {
      final sw = Stopwatch()..start();
      while (sw.elapsed < _railsTimeout) {
        final rails = container.read(sushiHomeRailsProvider);
        firstItem = [...rails.slider, ...rails.mostWatched, ...rails.trending].firstOrNull;
        if (firstItem != null) break;
        await tester.pump(const Duration(milliseconds: 300));
      }
      final homeRequests = sushiRequestCount;
      record(
        'home_rails_populate',
        firstItem != null && homeRequests <= _maxRequestsPerInteraction,
        firstItem == null
            ? 'no rails populated within $_railsTimeout (requests=$homeRequests)'
            : 'item="${firstItem.name}" requests=$homeRequests',
      );
    } catch (e) {
      record('home_rails_populate', false, 'error: $e');
    }

    if (firstItem == null) {
      // ignore: avoid_print
      print('[sushi-e2e] aborting — no home rail item to drive the rest of the suite with');
      final failures = results.entries.where((e) => e.value.startsWith('FAIL')).toList();
      expect(failures, isEmpty, reason: failures.map((e) => '${e.key}: ${e.value}').join('\n'));
      return;
    }
    final item = firstItem;

    // ---------------------------------------------------------------------
    // 2) Opening the detail screen (/item [+ /files]) stays within budget AND yields a model with
    //    playable media — the exact live bug report was a refresh leaving Play/info missing.
    // ---------------------------------------------------------------------
    MovieModel? detail;
    try {
      sushiResetRequestCounter();
      final notifier = container.read(movieDetailsProvider(item.id).notifier);
      await notifier.fetchDetails(item).timeout(_detailsTimeout);
      detail = container.read(movieDetailsProvider(item.id));
      final openRequests = sushiRequestCount;
      final playable = detail != null && sushiMovieHasPlayableMedia(detail);
      record(
        'item_open',
        playable && openRequests <= _maxRequestsPerInteraction,
        detail == null
            ? 'no detail model returned (requests=$openRequests)'
            : 'requests=$openRequests title="${detail.name}" playable=$playable',
      );
    } catch (e) {
      record('item_open', false, 'error: $e');
    }

    // ---------------------------------------------------------------------
    // 3) Pull-to-refresh: MovieDetailScreen's RefreshIndicator calls exactly this
    //    (fetchDetails(widget.item) again) — must not spam the bot, and must not lose Play/info.
    // ---------------------------------------------------------------------
    try {
      sushiResetRequestCounter();
      final notifier = container.read(movieDetailsProvider(item.id).notifier);
      await notifier.fetchDetails(detail ?? item).timeout(_detailsTimeout);
      final refreshed = container.read(movieDetailsProvider(item.id));
      final refreshRequests = sushiRequestCount;
      final playable = refreshed != null && sushiMovieHasPlayableMedia(refreshed);
      record(
        'item_refresh',
        playable && refreshRequests <= _maxRequestsPerInteraction,
        refreshed == null
            ? 'model disappeared after refresh — the reported bug (requests=$refreshRequests)'
            : 'requests=$refreshRequests title="${refreshed.name}" playable=$playable',
      );
      detail = refreshed ?? detail;
    } catch (e) {
      record('item_refresh', false, 'error: $e');
    }

    // ---------------------------------------------------------------------
    // 4) Play -> confirm real playback starts -> close -> repeat back-to-back. This is exactly the
    //    shape of the second bulkBarrierPreWrite crash: stopPlaybackSession's cleanup racing the
    //    next /item or /play call. A crash here kills the whole test process, which itself is a
    //    clear FAIL signal even before the `expect` below runs.
    // ---------------------------------------------------------------------
    if (detail != null && sushiMovieHasPlayableMedia(detail)) {
      try {
        var allOk = true;
        final details = <String>[];
        for (var i = 0; i < 3; i++) {
          final playedFuture = playerStates().firstWhere((s) => s.playing && !s.buffering);
          await detail.play(context, ref).timeout(_playTimeout);
          try {
            await playedFuture.timeout(_playTimeout);
            details.add('cycle$i=played');
          } catch (e) {
            allOk = false;
            details.add('cycle$i=FAILED_TO_PLAY($e)');
            break;
          }

          // Close the video the same way the player's own back button does — pop the root
          // navigator it was pushed onto (see play_item_helpers.dart's _playbackRootContext).
          final rootNavigator = Navigator.of(context, rootNavigator: true);
          if (rootNavigator.canPop()) {
            rootNavigator.pop();
          }
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
        record('play_close_stress', allOk, details.join(', '));
      } catch (e) {
        record('play_close_stress', false, 'error: $e');
      }
    } else {
      record('play_close_stress', false, 'skipped — no playable detail model from steps 2/3');
    }

    // ---------------------------------------------------------------------
    print('\n[sushi-e2e] ===== SUMMARY =====');
    for (final entry in results.entries) {
      print('[sushi-e2e] ${entry.key}: ${entry.value}');
    }
    final failures = results.entries.where((e) => e.value.startsWith('FAIL')).toList();
    expect(failures, isEmpty, reason: failures.map((e) => '${e.key}: ${e.value}').join('\n'));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
