import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_windows/webview_windows.dart' as win;

import 'package:fladder/sushi/sushi_http.dart';

/// In-app YouTube trailer player (ADR 0031): a WebView pointed at the youtube-nocookie.com embed,
/// never an external browser -- opening a system browser for a trailer is a jarring context switch
/// on Windows and close to broken on TV (remote-driven browser chrome, no easy way back to the app).
/// v1 uses YouTube's own embed controls: no JS bridge, no custom chrome.
///
/// webview_flutter has no Windows implementation (only android/ios/macos), so Windows goes through
/// webview_windows (WebView2) instead. Same embed URL either way.
class SushiTrailerPlayer extends StatefulWidget {
  const SushiTrailerPlayer({super.key, required this.youtubeKey, required this.title});

  final String youtubeKey;
  final String title;

  /// No-ops when [youtubeKey] is empty, so a call site can pass it through unconditionally.
  static Future<void> open(
    BuildContext context, {
    required String youtubeKey,
    required String title,
  }) {
    if (youtubeKey.isEmpty) return Future.value();
    // Root navigator sits above the TV side rail. The nested navigator leaves
    // the rail painted and focused on top of this route, so the embed never
    // receives the remote.
    return Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => SushiTrailerPlayer(youtubeKey: youtubeKey, title: title),
    ));
  }

  @override
  State<SushiTrailerPlayer> createState() => _SushiTrailerPlayerState();
}

class _SushiTrailerPlayerState extends State<SushiTrailerPlayer> {
  late final Uri _embedUri = Uri.https(
    'www.youtube-nocookie.com',
    '/embed/${widget.youtubeKey}',
    const {'rel': '0', 'playsinline': '1', 'autoplay': '1'},
  );

  WebViewController? _flutterController;
  win.WebviewController? _windowsController;
  bool _windowsReady = false;
  Object? _error;

  bool get _useWindows => !kIsWeb && Platform.isWindows;

  @override
  void initState() {
    super.initState();
    if (!sushiHttpUriAllowed(_embedUri)) {
      // Should never trip -- youtube-nocookie.com is on the allowlist (docs/09 R-SEC-12, ADR
      // 0031) -- but the player must never load a URL the allowlist itself would reject.
      _error = StateError('trailer url not on allowlist: $_embedUri');
      return;
    }
    if (_useWindows) {
      unawaited(_initWindows());
    } else {
      unawaited(_initFlutter());
    }
  }

  /// YouTube embed error 153 (`embedder.identity.missing.referrer`): a WebView sends no Referer
  /// unless one is set. YouTube requires `https://<applicationId>` (docs: embedded player identity).
  Future<void> _initFlutter() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    final referer = 'https://${info.packageName.toLowerCase()}';
    debugPrint('[sushi] trailer referer=$referer key=${widget.youtubeKey}');
    final controller = WebViewController();
    if (!kIsWeb && Platform.isAndroid && controller.platform is AndroidWebViewController) {
      final android = controller.platform as AndroidWebViewController;
      await android.setMediaPlaybackRequiresUserGesture(false);
    }
    if (!mounted) return;
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          // Only the embed player's own origin may load; a suggested video, the YouTube logo, or
          // "watch on YouTube" is refused rather than followed off the allowlisted host.
          final uri = Uri.tryParse(request.url);
          if (uri != null && uri.host.toLowerCase() == 'www.youtube-nocookie.com') {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(_embedUri, headers: {'Referer': referer});
    setState(() => _flutterController = controller);
  }

  Future<void> _initWindows() async {
    final controller = win.WebviewController();
    try {
      await controller.initialize();
      await controller.loadUrl(_embedUri.toString());
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _windowsController = controller;
        _windowsReady = true;
      });
    } catch (e, st) {
      debugPrint('[sushi] trailer webview_windows init failed: $e\n$st');
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    unawaited(_windowsController?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ExcludeFocus(
          child: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(widget.title, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
      body: SafeArea(
        child: Focus(
          autofocus: true,
          onKeyEvent: _onPlayerKey,
          child: _body(),
        ),
      ),
    );
  }

  /// TV remote Select/Enter never reaches the embed's HTML play button while
  /// Flutter still owns focus. Toggle the embed `<video>` from here.
  KeyEventResult _onPlayerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _flutterController == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final play = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA;
    if (!play) return KeyEventResult.ignored;
    unawaited(_flutterController!.runJavaScript(
      "(function(){var v=document.querySelector('video');if(v){if(v.paused){v.play();}else{v.pause();}return;}var b=document.querySelector('.ytp-large-play-button,.ytp-play-button');if(b)b.click();})();",
    ));
    return KeyEventResult.handled;
  }

  Widget _body() {
    if (_error != null) {
      return const Center(
        child: Text('Trailer unavailable', style: TextStyle(color: Colors.white70)),
      );
    }
    if (_useWindows) {
      final controller = _windowsController;
      if (!_windowsReady || controller == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return win.Webview(controller);
    }
    final controller = _flutterController;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return WebViewWidget(controller: controller);
  }
}
