import 'dart:convert';
import 'dart:js_interop';

/// Web-only DOM hooks for stream / video diagnostics.
/// Bootstrap lives in [web/sushi-playback-diag.js] (loaded from index.html).
abstract final class SushiPlaybackDiagHooks {
  static bool _installed = false;

  static void install() {
    if (_installed) return;
    try {
      _sushiPlaybackDiagInstall();
      _installed = true;
    } catch (e) {
      _installed = false;
    }
  }

  static void uninstall() {
    if (!_installed) return;
    try {
      _sushiPlaybackDiagUninstall();
    } catch (_) {}
    _installed = false;
  }

  static Map<String, Object?> snapshot() {
    if (!_installed) return const {};
    try {
      final raw = _sushiPlaybackDiagSnapshotJson();
      if (raw == null || raw.isEmpty) return const {};
      return _decodeMap(raw);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  static bool get isInstalled => _installed;

  static Future<Map<String, Object?>> probeCdnRange(String url) async {
    try {
      install();
      if (!_installed) {
        return {'url': url, 'ok': false, 'error': 'hooks_unavailable'};
      }
      final raw = await _sushiPlaybackDiagFetchRange(url.toJS).toDart;
      if (raw == null) return {'url': url, 'ok': false, 'error': 'empty_response'};
      return _decodeMap(raw.toDart);
    } catch (e) {
      return {'url': url, 'ok': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, Object?>> probeVideoLoad(String url) async {
    try {
      install();
      if (!_installed) {
        return {'url': url, 'ok': false, 'error': 'hooks_unavailable'};
      }
      final raw = await _sushiPlaybackDiagProbeVideo(url.toJS).toDart;
      if (raw == null) return {'url': url, 'ok': false, 'error': 'empty_response'};
      return _decodeMap(raw.toDart);
    } catch (e) {
      return {'url': url, 'ok': false, 'error': e.toString()};
    }
  }

  static Map<String, Object?> _decodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.cast<String, Object?>();
      }
    } catch (_) {}
    return {'raw': raw};
  }
}

@JS('window.__sushiPlaybackDiagInstall')
external void _sushiPlaybackDiagInstall();

@JS('window.__sushiPlaybackDiagUninstall')
external void _sushiPlaybackDiagUninstall();

@JS('window.__sushiPlaybackDiagSnapshotJson')
external String? _sushiPlaybackDiagSnapshotJson();

@JS('window.__sushiPlaybackDiagFetchRange')
external JSPromise<JSString?> _sushiPlaybackDiagFetchRange(JSString url);

@JS('window.__sushiPlaybackDiagProbeVideo')
external JSPromise<JSString?> _sushiPlaybackDiagProbeVideo(JSString url);
