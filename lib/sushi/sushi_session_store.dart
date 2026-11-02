import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/account_model.dart';

/// Persists OX refresh tokens outside Fladder's Jellyfin credentials blob.
class SushiSessionStore {
  SushiSessionStore(this._prefs);

  final SharedPreferences _prefs;

  static const _keyPrefix = 'ox_refresh_token_';

  String _key(AccountModel account) => '$_keyPrefix${account.credentials.serverId}:${account.id}';

  Future<void> save(AccountModel account, String refreshToken) async {
    final token = refreshToken.trim();
    if (token.isEmpty) return;
    await _prefs.setString(_key(account), token);
  }

  Future<String?> read(AccountModel account) async {
    final value = _prefs.getString(_key(account));
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> clear(AccountModel account) async {
    await _prefs.remove(_key(account));
  }
}
