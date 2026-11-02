import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_stream_log.dart';
import 'package:fladder/sushi/sushi_telegram_windows_ffi.dart';

/// Android stream_cb `dlopen`s `liboxtelegramstream.so`, a second Go runtime next to
/// gomobile's `libgojni.so`. Two Go runtimes in one process crash playback with
/// `fatal error: bulkBarrierPreWrite: unaligned arguments` (Pixel, 2026-09-21).
/// Kotlin `OX_TELEGRAM_STREAM_CB_ENABLED` is already false; do not load that .so
/// until the flag is on and the hang is fixed.
bool sushiTelegramStreamCbSupported(TargetPlatform platform) =>
    platform == TargetPlatform.windows;

/// C typedef: int (*)(mpv_handle*, const char*, void*, mpv_stream_cb_open_ro_fn)
typedef _MpvStreamCbAddRoNative = Int32 Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Void>,
  Pointer<NativeFunction<SushiStreamOpenFnNative>>,
);
typedef _MpvStreamCbAddRoDart = int Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Void>,
  Pointer<NativeFunction<SushiStreamOpenFnNative>>,
);

/// Registers the "gotdstream://" protocol (backed by oxtelegram.dll's stream_cb callbacks — see
/// go/oxtelegram/cshared/stream_cb.go) on one libmpv instance, so mpv reads Telegram bytes via
/// direct in-process callbacks instead of the loopback HTTP bridge.
///
/// mpv_stream_cb_add_ro is per mpv_handle, not process-global (see upstream stream_cb.h: "The
/// callback remains registered until the mpv core is [terminated]" — scoped to the instance it
/// was added to). Every place LibMPV creates a new mpv.Player needs its own call to
/// [registerOn] with that player's own handle: today that's `init()` and `crossfadeToUrl()`'s
/// `incomingPlayer` — missing either one leaves that specific player's `gotdstream://` loads
/// failing with MPV_ERROR_LOADING_FAILED while looking otherwise fine.
///
/// Registration itself is Windows-only today. media_kit's `Player.handle` works the same on
/// Android, but loading `liboxtelegramstream.so` starts a second Go runtime next to gomobile
/// (`sushiTelegramStreamCbSupported`). Re-enable Android only with `OX_TELEGRAM_STREAM_CB_ENABLED`
/// after that hang is fixed.
class SushiTelegramStreamCb {
  static const _protocol = 'gotdstream';
  static const _kMpvStreamCbAddRoSymbol = 'mpv_stream_cb_add_ro';
  static _MpvStreamCbAddRoDart? _addRo;
  static Pointer<NativeFunction<SushiStreamOpenFnNative>>? _openFnAddress;

  static _MpvStreamCbAddRoDart _resolveMpvStreamCbAddRo() {
    final cached = _addRo;
    if (cached != null) return cached;
    DynamicLibrary? lib;
    // DynamicLibrary.process() resolves symbols against whatever is already mapped into this
    // process — critically, the *exact same* libmpv module media_kit itself loaded, not a
    // possibly-distinct module instance. Confirmed the hard way: reopening "libmpv-2.dll" by
    // bare name below returned mpv_stream_cb_add_ro, and it returned rc=0 (success) when called,
    // yet mpv's own stream layer reported the protocol as unregistered moments later — consistent
    // with that lookup and player.handle's ctx not agreeing on which loaded module is "the" mpv.
    // Keep the by-name candidates only as a fallback for platforms where .process() might not
    // resolve process-wide symbols the same way.
    try {
      lib = DynamicLibrary.process();
      lib.lookup(_kMpvStreamCbAddRoSymbol);
    } catch (_) {
      lib = null;
    }
    if (lib == null) {
      // Same candidate names/order media_kit's NativeLibrary.ensureInitialized tries.
      final candidates = Platform.isWindows
          ? const ['libmpv-2.dll', 'mpv-2.dll', 'mpv-1.dll']
          : const ['libmpv.so', 'libmpv.so.2', 'libmpv.so.1'];
      for (final name in candidates) {
        try {
          lib = DynamicLibrary.open(name);
          break;
        } catch (_) {
          continue;
        }
      }
    }
    if (lib == null) {
      throw StateError('SushiTelegramStreamCb: could not locate libmpv (expected already loaded by media_kit)');
    }
    final fn = lib.lookupFunction<_MpvStreamCbAddRoNative, _MpvStreamCbAddRoDart>(_kMpvStreamCbAddRoSymbol);
    _addRo = fn;
    return fn;
  }

  static Pointer<NativeFunction<SushiStreamOpenFnNative>> _resolveOpenFnAddress() {
    final cached = _openFnAddress;
    if (cached != null) return cached;
    final Pointer<NativeFunction<SushiStreamOpenFnNative>> address;
    if (Platform.isWindows) {
      address = SushiTelegramNative.instance().streamOpenFnAddress;
    } else {
      throw StateError(
        'SushiTelegramStreamCb: ox_stream_open_fn is Windows-only (R-UI-16). '
        'Android must not dlopen liboxtelegramstream.so next to gomobile.',
      );
    }
    _openFnAddress = address;
    return address;
  }

  /// Registers on the given raw mpv_handle address (from `player.handle`; see media_kit's
  /// `Player.handle`, backed by `ctx.address`). Safe to call more than once for the same handle: mpv
  /// returns MPV_ERROR_INVALID_PARAMETER (-4) for a protocol already registered on that instance,
  /// which this treats as expected, not a failure.
  static void registerOn(int mpvHandleAddress) {
    SushiStreamLog.event('stream_cb_register_attempt', fields: {
      'handle': mpvHandleAddress,
      'isWindows': Platform.isWindows,
      'isAndroid': Platform.isAndroid,
    });
    if (!Platform.isWindows) return;
    try {
      final addRo = _resolveMpvStreamCbAddRo();
      final openFnAddress = _resolveOpenFnAddress();
      SushiStreamLog.event('stream_cb_register_resolved', fields: {
        'openFnAddress': openFnAddress.address,
      });
      final protocol = _protocol.toNativeUtf8();
      try {
        final rc = addRo(
          Pointer<Void>.fromAddress(mpvHandleAddress),
          protocol,
          nullptr,
          openFnAddress,
        );
        SushiStreamLog.event('stream_cb_register_result', fields: {'rc': rc});
        if (rc != 0 && rc != -4) {
          SushiStreamLog.event('stream_cb_register_failed', fields: {'rc': rc});
        }
      } finally {
        malloc.free(protocol);
      }
    } catch (error) {
      SushiStreamLog.event('stream_cb_register_error', fields: {'error': error.toString()});
    }
  }

  /// `gotdstream://{id}` for the currently active oxtelegram playback session, or null if none —
  /// mirrors sushiIsTdlibHttpBridgeUrl's role for the HTTP bridge path.
  static String? currentStreamUri() {
    if (!Platform.isWindows) return null;
    try {
      final native = SushiTelegramNative.instance();
      final ptr = native.streamUriForCurrentPlayback();
      if (ptr == nullptr) return null;
      return native.readCString(ptr);
    } catch (_) {
      return null;
    }
  }
}
