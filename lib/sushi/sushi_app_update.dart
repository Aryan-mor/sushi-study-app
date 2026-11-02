import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'package:fladder/sushi/widgets/sushi_dialog_focus_trap.dart';
import 'package:fladder/sushi/sushi_app_platform.dart';
import 'package:fladder/sushi/sushi_app_update_pb.dart';
import 'package:fladder/sushi/sushi_app_update_transport.dart';
import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_semver.dart';
import 'package:fladder/sushi/sushi_tdlib_playback_resolver.dart'
    show sushiIsTdlibFileMissingError, sushiIsTelegramDeliveryWaitTimeoutError;
import 'package:fladder/src/tdlib_bridge.g.dart';

export 'package:fladder/sushi/sushi_app_platform.dart' show sushiAppUpdateLocator;
export 'package:fladder/sushi/sushi_app_update_pb.dart' show SushiLatestApp;

const _kSkippedVersionKey = 'sushi_skipped_app_version';
const _kLatestAppVersionKey = 'sushi_latest_app_version';
const _kLatestAppPlatformKey = 'sushi_latest_app_platform';

/// Latest shelf version from HomeRes. Null until the first home answer that carried one.
final ValueNotifier<SushiLatestApp?> sushiLatestApp = ValueNotifier<SushiLatestApp?>(null);

SharedPreferences? _updatePrefs;
String _updateCurrentVersion = '';

String sushiUpdateCurrentVersion() => _updateCurrentVersion;

/// Called once from bootstrap so the prompt host can skip/compare without a Riverpod read.
void sushiBindUpdatePrompt(SharedPreferences prefs, String currentVersion) {
  _updatePrefs = prefs;
  _updateCurrentVersion = currentVersion;
  final version = (prefs.getString(_kLatestAppVersionKey) ?? '').trim();
  if (version.isEmpty) return;
  sushiLatestApp.value = SushiLatestApp(
    platform: prefs.getString(_kLatestAppPlatformKey) ?? '',
    version: version,
  );
}

GlobalKey<NavigatorState>? _updateNavigatorKey;
Listenable? _updateRouteListenable;
String Function()? _updateCurrentRouteName;
VoidCallback? _updateRouteListener;
Future<void> Function()? _latestAppRefresher;

/// Dashboard tab of HomeScreen. Favourites / details / player / settings are not "home"
/// for the automatic prompt — TV users often resume onto a pushed route.
const sushiUpdateHomeRouteName = 'DashboardRoute';

/// TV Home (and Android recents) leaves the process alive. After this long in background,
/// hit `/home` again so `latest_app` can change without a cold start.
const sushiUpdateResumeRecheckAfter = Duration(minutes: 5);

bool sushiIsUpdateHomeRoute(String? routeName) => routeName == sushiUpdateHomeRouteName;

bool sushiShouldRecheckUpdateOnResume({
  required DateTime? pausedAt,
  required DateTime now,
  Duration minBackground = sushiUpdateResumeRecheckAfter,
}) {
  if (pausedAt == null) return false;
  return !now.difference(pausedAt).isNegative && now.difference(pausedAt) >= minBackground;
}

/// Registered from `MaterialApp.router` (the route Navigator's own key) so the automatic
/// prompt can show over a context that actually sits below a Navigator. [SushiUpdatePromptHost]
/// wraps `MaterialApp.router` from the outside, so its own `State.context` has no Navigator
/// ancestor — `showDialog` with that context silently fails to find one and throws.
///
/// [routeListenable] + [currentRouteName] defer the prompt until the user is on dashboard.
void sushiRegisterUpdateNavigatorKey(
  GlobalKey<NavigatorState> key, {
  Listenable? routeListenable,
  String Function()? currentRouteName,
}) {
  _updateNavigatorKey = key;
  _updateCurrentRouteName = currentRouteName;
  if (identical(_updateRouteListenable, routeListenable)) return;
  final listener = _updateRouteListener;
  if (listener != null) {
    _updateRouteListenable?.removeListener(listener);
  }
  _updateRouteListenable = routeListenable;
  if (listener != null) {
    _updateRouteListenable?.addListener(listener);
  }
}

/// One `/home` round-trip that stamps [sushiLatestApp]. Bound from bootstrap so this
/// library does not import the home transport (that file already imports us).
void sushiBindLatestAppRefresher(Future<void> Function() refresh) {
  _latestAppRefresher = refresh;
}

/// Called from the home transport whenever a HomeRes includes latest_app (ADR 0019).
Future<void> sushiNoteLatestApp(SushiLatestApp? latest) async {
  if (latest == null || latest.version.isEmpty) return;
  sushiLatestApp.value = latest;
  final prefs = _updatePrefs;
  if (prefs == null) return;
  await prefs.setString(_kLatestAppVersionKey, latest.version);
  await prefs.setString(_kLatestAppPlatformKey, latest.platform);
}

Future<void> sushiClearPersistedLatestApp() async {
  sushiLatestApp.value = null;
  try {
    final prefs = _updatePrefs ?? await SharedPreferences.getInstance();
    await prefs.remove(_kLatestAppVersionKey);
    await prefs.remove(_kLatestAppPlatformKey);
  } catch (_) {}
}

final RegExp _nightlySerial = RegExp(r'-nightly(?:\.(\d+))?$', caseSensitive: false);

/// Null when [raw] is a stable version. `0` for a bare `-nightly`. The trailing integer is the
/// CI version code (`1.2.0-nightly.15234`), so a later nightly of the same semver still prompts.
int? sushiNightlySerial(String raw) {
  final match = _nightlySerial.firstMatch(raw.trim().split('+').first);
  if (match == null) return null;
  final digits = match.group(1);
  if (digits == null) return 0;
  return int.tryParse(digits);
}

bool sushiIsNewerApp(String currentVersion, String latestVersion) {
  final current = SushiSemver.parse(currentVersion) ?? const SushiSemver(major: 0, minor: 0, patch: 0);
  final latest = SushiSemver.parse(latestVersion);
  if (latest == null) return false;
  if (latest.isNewerThan(current)) return true;
  if (current.isNewerThan(latest)) return false;
  // Same numbers. Android's versionName is the plain semver (build.gradle), while the shelf
  // version is `M.m.p-nightly.<code>`. Treating that suffix as newer loops the prompt forever
  // after the tester installs the build. A later nightly bumps the patch, so it still prompts.
  // Two nightlies that both carry a serial still compare those serials.
  final latestNightly = sushiNightlySerial(latestVersion);
  final currentNightly = sushiNightlySerial(currentVersion);
  if (latestNightly == null || currentNightly == null) return false;
  return latestNightly > currentNightly;
}

Future<bool> sushiShouldOfferUpdate({
  required String currentVersion,
  required SharedPreferences prefs,
}) async {
  final latest = sushiLatestApp.value;
  if (latest == null || !sushiIsNewerApp(currentVersion, latest.version)) return false;
  return prefs.getString(_kSkippedVersionKey) != latest.version;
}

Future<void> sushiSkipAppVersion(SharedPreferences prefs, String version) {
  return prefs.setString(_kSkippedVersionKey, version);
}

/// Cold /appupdate session: never pass copyMessage's id. That id is the *sender's* numbering;
/// native `getMessages` uses the receiver's, so a protocol-chat text message sits at that number
/// (`OX_DM_STALE: dm message N has no document`). 0/0 waits on the locator push instead — same
/// as a cold `/play`. Arm [sushiArmDeliveryWaiter] *before* `/appupdate`.
SushiTdlibPlaybackSource sushiAppUpdateColdSource(String locator) {
  return SushiTdlibPlaybackSource(
    providerBotId: 0,
    messageId: 0,
    preferHttpBridge: true,
    locator: locator,
  );
}

/// Copies the shelf file into the protocol chat, pulls it over MTProto, installs.
Future<void> sushiInstallLatestApp({
  required void Function(double? progress) onProgress,
}) async {
  final platform = await sushiAppPlatform();
  if (platform.isEmpty) {
    throw StateError('appupdate: unknown platform');
  }
  final version = (sushiLatestApp.value?.version ?? '').trim();
  final locator = sushiAppUpdateLocator(platform, version);
  await sushiArmDeliveryWaiter(locator);

  var res = await sushiFetchAppUpdate(platform: platform);
  if (res == null || res.messageId == 0) {
    throw StateError('appupdate: no file');
  }
  var loc = res.locator.isNotEmpty ? res.locator : locator;
  if (loc != locator) {
    await sushiArmDeliveryWaiter(loc);
  }

  String url;
  try {
    url = await sushiStartPlaybackSession(sushiAppUpdateColdSource(loc));
  } catch (e) {
    if (!sushiIsTdlibFileMissingError(e) && !sushiIsTelegramDeliveryWaitTimeoutError(e)) {
      rethrow;
    }
    debugPrint('[sushi] appupdate waiting for landed copy: $e');
    final landed = await _pollAppUpdateDeliveryRef(loc);
    if (landed != null && landed.messageId > 0 && landed.providerBotId > 0) {
      url = await sushiStartPlaybackSession(SushiTdlibPlaybackSource(
        providerBotId: landed.providerBotId,
        messageId: landed.messageId,
        preferHttpBridge: true,
        locator: loc,
      ));
    } else {
      await sushiArmDeliveryWaiter(loc);
      final retry = await sushiFetchAppUpdate(platform: platform);
      if (retry == null || retry.messageId == 0) rethrow;
      res = retry;
      if (retry.locator.isNotEmpty) loc = retry.locator;
      url = await sushiStartPlaybackSession(sushiAppUpdateColdSource(loc));
    }
  }

  try {
    final file = await _downloadLocalhost(url, res.fileName, onProgress);
    onProgress(1);
    await _installFile(file);
  } finally {
    await sushiStopPlaybackSession(url);
  }
}

Future<SushiTdlibDeliveryRef?> _pollAppUpdateDeliveryRef(
  String locator, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final ref = await sushiDeliveryRefForLocator(locator);
    if (ref != null && ref.messageId > 0 && ref.providerBotId > 0) {
      return ref;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return sushiDeliveryRefForLocator(locator);
}

/// Total object size from a bridge response. Content-Range wins: the Windows HTTP bridge
/// answers an open range with 206 and an 8 MiB body, while `/{total}` is the real file.
int? sushiAppUpdateBodyTotal(String? contentRange, int contentLength, int already) {
  if (contentRange != null) {
    final slash = contentRange.lastIndexOf('/');
    if (slash >= 0) {
      final n = int.tryParse(contentRange.substring(slash + 1).trim());
      if (n != null && n > 0) return n;
    }
  }
  if (contentLength > 0) return already + contentLength;
  return null;
}

Future<File> _downloadLocalhost(
  String url,
  String fileName,
  void Function(double? progress) onProgress,
) async {
  final uri = Uri.parse(url);
  if (uri.host != '127.0.0.1' && uri.host != 'localhost') {
    throw StateError('appupdate: expected localhost bridge, got ${uri.host}');
  }
  final dir = await getTemporaryDirectory();
  var safe = fileName.isEmpty ? 'sushi_update.apk' : fileName.replaceAll(RegExp(r'[/\\]'), '_');
  if (!safe.contains('.')) safe = '$safe.apk';
  final out = File('${dir.path}/$safe');
  final client = HttpClient();
  final sink = out.openWrite();
  try {
    var got = 0;
    int? total;
    while (true) {
      final req = await client.getUrl(uri);
      if (got > 0 && total != null) {
        // Explicit end. An open range (`bytes=N-`) is capped at 8 MiB on the Windows bridge.
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$got-${total - 1}');
      }
      final resp = await req.close();
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw StateError('appupdate: download HTTP ${resp.statusCode}');
      }
      final declared = sushiAppUpdateBodyTotal(
        resp.headers.value(HttpHeaders.contentRangeHeader),
        resp.contentLength,
        got,
      );
      if (declared != null) total = declared;
      final before = got;
      await for (final chunk in resp) {
        sink.add(chunk);
        got += chunk.length;
        if (total != null && total > 0) onProgress(got / total);
      }
      if (resp.statusCode == 200 || (total != null && got >= total)) break;
      if (got == before || total == null) {
        throw StateError('appupdate: download stalled at $got');
      }
    }
    await sink.close();
    return out;
  } catch (e) {
    await sink.close();
    if (out.existsSync()) {
      try {
        out.deleteSync();
      } catch (_) {}
    }
    rethrow;
  } finally {
    client.close(force: true);
  }
}

Future<void> _installFile(File file) async {
  if (Platform.isAndroid) {
    final status = await Permission.requestInstallPackages.status;
    if (!status.isGranted) {
      final next = await Permission.requestInstallPackages.request();
      if (!next.isGranted) {
        throw StateError('Could not launch the Android package installer');
      }
    }
    final opened = await FileDownloader().openFile(
      filePath: file.path,
      mimeType: 'application/vnd.android.package-archive',
    );
    if (!opened) {
      throw StateError('Could not launch the Android package installer');
    }
    return;
  }
  if (Platform.isWindows) {
    // ProcessStartMode.detached stays in the parent's Windows job. windowManager.close()
    // then kills the installer before Inno can replace fladder.exe. `start` breaks the
    // setup process out of that job. Wait until cmd returns so setup is already running.
    final launch = await Process.run('cmd.exe', [
      '/c',
      'start',
      '',
      '/b',
      file.path,
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      '/RESTARTAPPLICATIONS',
    ]);
    if (launch.exitCode != 0) {
      final detail = (launch.stderr as String).trim();
      throw StateError(
        detail.isEmpty
            ? 'Could not launch the Windows installer (exit ${launch.exitCode})'
            : 'Could not launch the Windows installer (exit ${launch.exitCode}): $detail',
      );
    }
    await windowManager.close();
    return;
  }
  throw StateError('in-app install is not supported on this platform');
}

/// `/start download` rest. Main-bot answers with the platform APK picker, not Home.
const sushiMainBotDownloadStart = 'download';

Uri sushiMainBotDownloadTgUri() {
  return Uri.parse(
    'tg://resolve?domain=${SushiConfig.mainBotUsername}&start=$sushiMainBotDownloadStart',
  );
}

Future<void> sushiOpenMainBotDownload() async {
  final uri = sushiMainBotDownloadTgUri();
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    await launchUrl(
      Uri.parse(SushiConfig.mainBotAppCodeUrl(sushiMainBotDownloadStart)),
      mode: LaunchMode.externalApplication,
    );
  }
}

/// EN + FA copy for the update surfaces (R-I18N-1).
class SushiUpdateCopy {
  const SushiUpdateCopy(this._fa);

  factory SushiUpdateCopy.of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return SushiUpdateCopy(code.toLowerCase().startsWith('fa'));
  }

  final bool _fa;

  String get bannerTitle => _fa ? 'نسخه جدید سوشی' : 'New Sushi version';
  String bannerSub(String version) =>
      _fa ? 'سوشی $version آماده‌ست. از همین‌جا نصبش کن.' : 'Sushi $version is ready. Install it here.';
  String get dialogTitle => _fa ? 'نسخه جدید' : 'Update available';
  String dialogBody(String current, String latest) => _fa
      ? 'الان $current داری. $latest بهتره. دانلود و نصب از تلگرام، بدون سایت.'
      : 'You have $current. $latest is newer. Download and install through Telegram — no website.';
  String get install => _fa ? 'دانلود و نصب' : 'Download and install';
  String get skip => _fa ? 'فعلا نه' : 'Not now';
  String get later => _fa ? 'بعدا' : 'Later';
  String get downloading => _fa ? 'داره میاد…' : 'Downloading…';
  String get installing => _fa ? 'داره نصب میشه…' : 'Installing…';
  String get installingHint => _fa
      ? 'اپ الان بسته می‌شه و بعدش خودش خودکار باز می‌شه.'
      : 'The app will close now and open again on its own.';
  String get failed => _fa ? 'دانلود نشد. از اپ دانلود کن.' : 'Download failed. Get it from the bot.';
  String get openBot => _fa ? 'از اپ دانلود کن' : 'Download the app';
}

Future<void> sushiShowUpdateDialog({
  required BuildContext context,
  required String currentVersion,
  required SharedPreferences prefs,
}) async {
  final latest = sushiLatestApp.value;
  if (latest == null || !context.mounted) return;
  final copy = SushiUpdateCopy.of(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => SushiDialogFocusTrap(
      child: _SushiUpdateDialog(
        copy: copy,
        currentVersion: currentVersion,
        latestVersion: latest.version,
        prefs: prefs,
      ),
    ),
  );
}

class _SushiUpdateDialog extends StatefulWidget {
  const _SushiUpdateDialog({
    required this.copy,
    required this.currentVersion,
    required this.latestVersion,
    required this.prefs,
  });

  final SushiUpdateCopy copy;
  final String currentVersion;
  final String latestVersion;
  final SharedPreferences prefs;

  @override
  State<_SushiUpdateDialog> createState() => _SushiUpdateDialogState();
}

enum _Phase { ask, downloading, installing, error }

class _SushiUpdateDialogState extends State<_SushiUpdateDialog> {
  _Phase _phase = _Phase.ask;
  double? _progress;

  Future<void> _install() async {
    setState(() {
      _phase = _Phase.downloading;
      _progress = null;
    });
    try {
      await sushiInstallLatestApp(onProgress: (p) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          if (p != null && p >= 1) _phase = _Phase.installing;
        });
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      debugPrint('[sushi] update install failed: $e\n$st');
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    if (_phase == _Phase.ask) {
      return AlertDialog(
        title: Text(copy.dialogTitle),
        content: Text(copy.dialogBody(widget.currentVersion, widget.latestVersion)),
        actions: [
          TextButton(
            onPressed: () async {
              await sushiSkipAppVersion(widget.prefs, widget.latestVersion);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(copy.skip),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(copy.later),
          ),
          FilledButton(onPressed: _install, child: Text(copy.install)),
        ],
      );
    }
    if (_phase == _Phase.error) {
      return AlertDialog(
        title: Text(copy.failed),
        actions: [
          TextButton(
            onPressed: () async {
              await sushiOpenMainBotDownload();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(copy.openBot),
          ),
          FilledButton(onPressed: _install, child: Text(copy.install)),
        ],
      );
    }
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(_phase == _Phase.installing ? copy.installing : copy.downloading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: _progress),
            if (_phase == _Phase.installing) ...[
              const SizedBox(height: 12),
              Text(copy.installingHint),
            ],
            if (_progress != null) ...[
              const SizedBox(height: 8),
              Text('${((_progress ?? 0) * 100).round()}%'),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wraps the app so a newer HomeRes can prompt on the dashboard — including after a
/// TV Home resume, where the process never died and the first-frame `_shown` latch
/// used to swallow the next shelf version.
class SushiUpdatePromptHost extends StatefulWidget {
  const SushiUpdatePromptHost({required this.child, super.key});

  final Widget child;

  @override
  State<SushiUpdatePromptHost> createState() => _SushiUpdatePromptHostState();
}

class _SushiUpdatePromptHostState extends State<SushiUpdatePromptHost> with WidgetsBindingObserver {
  String? _offeredVersion;
  bool _dialogOpen = false;
  bool _showing = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sushiLatestApp.addListener(_onLatestApp);
    _updateRouteListener = _onRouteChanged;
    _updateRouteListenable?.addListener(_onRouteChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_maybeShow()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    sushiLatestApp.removeListener(_onLatestApp);
    final listener = _updateRouteListener;
    if (listener != null) {
      _updateRouteListenable?.removeListener(listener);
      if (identical(_updateRouteListener, listener)) {
        _updateRouteListener = null;
      }
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResumed());
    }
  }

  void _onLatestApp() => unawaited(_maybeShow());

  void _onRouteChanged() => unawaited(_maybeShow());

  String? _currentRouteName() {
    try {
      return _updateCurrentRouteName?.call();
    } catch (_) {
      return null;
    }
  }

  Future<void> _onResumed() async {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    final recheck = sushiShouldRecheckUpdateOnResume(pausedAt: pausedAt, now: DateTime.now());
    if (recheck) {
      // Later (not Skip) should re-appear after a long TV-home nap.
      _offeredVersion = null;
      unawaited(_maybeShow());
      final refresh = _latestAppRefresher;
      if (refresh != null) {
        try {
          await refresh();
        } catch (e, st) {
          debugPrint('[sushi] update recheck failed: $e\n$st');
        }
      }
    }
    if (!mounted) return;
    await _maybeShow();
  }

  Future<void> _maybeShow() async {
    if (!mounted || _dialogOpen || _showing) return;
    final prefs = _updatePrefs;
    if (prefs == null || _updateCurrentVersion.isEmpty) return;
    if (!await sushiShouldOfferUpdate(currentVersion: _updateCurrentVersion, prefs: prefs)) {
      return;
    }
    final latest = sushiLatestApp.value;
    if (latest == null) return;
    if (_offeredVersion == latest.version) return;

    final navContext = _updateNavigatorKey?.currentContext;
    if (navContext == null || !navContext.mounted || Navigator.maybeOf(navContext) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_maybeShow()));
      return;
    }
    if (!sushiIsUpdateHomeRoute(_currentRouteName())) return;

    _showing = true;
    _offeredVersion = latest.version;
    _dialogOpen = true;
    try {
      await sushiShowUpdateDialog(
        context: navContext,
        currentVersion: _updateCurrentVersion,
        prefs: prefs,
      );
    } finally {
      _dialogOpen = false;
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
