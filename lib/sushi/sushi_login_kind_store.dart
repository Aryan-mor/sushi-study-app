import 'package:shared_preferences/shared_preferences.dart';

/// How this device signed in — Telegram user session (phone/QR) vs main-bot approval.
enum SushiLoginKind {
  session,
  bot;

  static SushiLoginKind? tryParse(String? raw) {
    return switch (raw) {
      'session' => SushiLoginKind.session,
      'bot' => SushiLoginKind.bot,
      _ => null,
    };
  }
}

abstract final class SushiLoginKindStore {
  // Legacy prefs keys kept so upgrades keep stored login kind.
  static const _keyPrefix = 'ox_login_kind_';
  static const _currentKey = 'ox_login_kind_current';

  static Future<void> save({
    required String accountId,
    required SushiLoginKind kind,
  }) async {
    final id = accountId.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyPrefix$id', kind.name);
    await prefs.setString(_currentKey, kind.name);
  }

  static Future<SushiLoginKind?> read(String? accountId) async {
    final id = accountId?.trim() ?? '';
    if (id.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    return SushiLoginKind.tryParse(prefs.getString('$_keyPrefix$id'));
  }

  /// Last saved kind on this device, even before native TDLib is bot-ready.
  /// PlaybackInfo interceptor uses this so a main-bot code login does not get
  /// routed to kind=session while the personal-bot session is still applying.
  static Future<SushiLoginKind?> readCurrent() async {
    final prefs = await SharedPreferences.getInstance();
    return SushiLoginKind.tryParse(prefs.getString(_currentKey));
  }

  /// Copies the per-account kind onto [_currentKey] so PlaybackInfo can read it
  /// after an APK upgrade that introduced the current key.
  static Future<void> promoteToCurrent(String? accountId) async {
    final kind = await read(accountId);
    if (kind == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentKey, kind.name);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = [
      for (final key in prefs.getKeys())
        if (key == _currentKey || key.startsWith(_keyPrefix)) key,
    ];
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Stored kind wins. Else: personal-bot token ≈ bot login; TDLib ready as a user ≈ session.
  /// Native still waiting for phone (no user session) ≈ bot without /connectbot.
  static Future<SushiLoginKind?> resolve({
    required String? accountId,
    required bool tdlibUserSessionReady,
    required bool hasBotToken,
    required bool nativeWaitingForUserAuth,
  }) async {
    final stored = await read(accountId);
    if (stored != null) return stored;
    if (hasBotToken) return SushiLoginKind.bot;
    if (tdlibUserSessionReady) return SushiLoginKind.session;
    if (nativeWaitingForUserAuth) return SushiLoginKind.bot;
    return null;
  }
}
