import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/sushi/sushi_app_update.dart';
import 'package:fladder/sushi/sushi_app_update_pb.dart';
import 'package:fladder/sushi/sushi_config.dart';

void main() {
  tearDown(() {
    sushiLatestApp.value = null;
  });

  test('sushiUpdateHomeRouteName matches generated DashboardRoute', () {
    expect(sushiUpdateHomeRouteName, DashboardRoute.name);
  });

  test('sushiIsUpdateHomeRoute is dashboard only', () {
    expect(sushiIsUpdateHomeRoute('DashboardRoute'), isTrue);
    expect(sushiIsUpdateHomeRoute(DetailsRoute.name), isFalse);
    expect(sushiIsUpdateHomeRoute(FavouritesRoute.name), isFalse);
    expect(sushiIsUpdateHomeRoute(null), isFalse);
    expect(sushiIsUpdateHomeRoute(''), isFalse);
  });

  test('sushiShouldRecheckUpdateOnResume needs a long enough pause', () {
    final now = DateTime.utc(2026, 9, 16, 12);
    expect(
      sushiShouldRecheckUpdateOnResume(pausedAt: null, now: now),
      isFalse,
    );
    expect(
      sushiShouldRecheckUpdateOnResume(
        pausedAt: now.subtract(const Duration(minutes: 4, seconds: 59)),
        now: now,
      ),
      isFalse,
    );
    expect(
      sushiShouldRecheckUpdateOnResume(
        pausedAt: now.subtract(sushiUpdateResumeRecheckAfter),
        now: now,
      ),
      isTrue,
    );
    expect(
      sushiShouldRecheckUpdateOnResume(
        pausedAt: now.subtract(const Duration(hours: 2)),
        now: now,
      ),
      isTrue,
    );
  });

  test('sushiShouldOfferUpdate skips a version the user dismissed', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await sushiNoteLatestApp(const SushiLatestApp(platform: 'android_tv', version: '2.0.0'));

    expect(await sushiShouldOfferUpdate(currentVersion: '1.9.0', prefs: prefs), isTrue);

    await sushiSkipAppVersion(prefs, '2.0.0');
    expect(await sushiShouldOfferUpdate(currentVersion: '1.9.0', prefs: prefs), isFalse);

    await sushiNoteLatestApp(const SushiLatestApp(platform: 'android_tv', version: '2.1.0'));
    expect(await sushiShouldOfferUpdate(currentVersion: '1.9.0', prefs: prefs), isTrue);
  });

  test('sushiBindUpdatePrompt restores last latest_app so cold start can prompt', () async {
    SharedPreferences.setMockInitialValues({
      'sushi_latest_app_version': '1.1.192',
      'sushi_latest_app_platform': 'android_new',
    });
    final prefs = await SharedPreferences.getInstance();
    sushiBindUpdatePrompt(prefs, '1.1.191');
    expect(sushiLatestApp.value?.version, '1.1.192');
    expect(await sushiShouldOfferUpdate(currentVersion: '1.1.191', prefs: prefs), isTrue);
  });

  test('install-error open-bot deep link carries start=download', () {
    expect(sushiMainBotDownloadStart, 'download');
    final tg = sushiMainBotDownloadTgUri();
    expect(tg.scheme, 'tg');
    expect(tg.host, 'resolve');
    expect(tg.queryParameters['domain'], SushiConfig.mainBotUsername);
    expect(tg.queryParameters['start'], 'download');
    expect(
      SushiConfig.mainBotAppCodeUrl(sushiMainBotDownloadStart),
      'https://t.me/${SushiConfig.mainBotUsername}?start=download',
    );
  });

  test('error copy names the download-from-app action', () {
    const fa = SushiUpdateCopy(true);
    const en = SushiUpdateCopy(false);
    expect(fa.openBot, 'از اپ دانلود کن');
    expect(en.openBot, 'Download the app');
  });

  test('sushiClearPersistedLatestApp drops the shelf stamp', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    sushiBindUpdatePrompt(prefs, '1.1.191');
    await sushiNoteLatestApp(const SushiLatestApp(platform: 'android_new', version: '1.1.192'));
    await sushiClearPersistedLatestApp();
    expect(sushiLatestApp.value, isNull);
    expect(prefs.getString('sushi_latest_app_version'), isNull);
  });
}
