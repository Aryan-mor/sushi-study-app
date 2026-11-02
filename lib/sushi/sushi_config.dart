/// Master switch for Sushi-specific behavior (Telegram-native, no HTTP API).
///
/// Hardcoded on — this fork is always Sushi. Handles baked in per R-SEC-6 / ADR 0004.
///
/// Store flavors (`production`, `direct`) always use baked handles
/// (`exampleMainBot` / `exampleInit01Bot` unless `--dart-define`).
/// `development` (and flavor-less local runs) read `assets/env/default.env`
/// (`SUSHI_MAIN_BOT` / `SUSHI_INIT_BOT` from the README setup).
import 'package:fladder/sushi/sushi_dotenv.dart';

abstract final class SushiConfig {
  static const bool isEnabled = true;

  static const String _bakedMain = String.fromEnvironment(
    'SUSHI_MAIN_BOT',
    defaultValue: 'exampleMainBot',
  );
  static const String _bakedInit = String.fromEnvironment(
    'SUSHI_INIT_BOT',
    defaultValue: 'exampleInit01Bot',
  );
  static const String _flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');

  static String _handle(String raw) => raw.trim().replaceFirst(RegExp(r'^@'), '');

  /// Store / CI APKs (`production` Play, `direct` GitHub/website) must not follow a
  /// leftover local `default.env` (dev handles).
  static bool get _allowEnvHandles =>
      _flavor != 'production' && _flavor != 'direct';

  /// Public main-bot handle (no @).
  static String get mainBotUsername {
    if (_allowEnvHandles) {
      final fromEnv = _handle(SushiDotenv.get('SUSHI_MAIN_BOT'));
      if (fromEnv.isNotEmpty) return fromEnv;
    }
    return _handle(_bakedMain);
  }

  /// Init-bot handle (no @). Machine handshake only (`/initbot`).
  static String get initBotUsername {
    if (_allowEnvHandles) {
      final fromEnv = _handle(SushiDotenv.get('SUSHI_INIT_BOT'));
      if (fromEnv.isNotEmpty) return fromEnv;
    }
    return _handle(_bakedInit);
  }

  /// Public preview channel (ADR 0013). Same handle in every environment.
  static const String loginChannelUsername = String.fromEnvironment(
    'SUSHI_LOGIN_CHANNEL',
    defaultValue: 'exampleLoginChannel',
  );

  /// Public channel the About page sends support and takedown notices to.
  static const String supportChannelUsername = String.fromEnvironment(
    'SUSHI_SUPPORT_CHANNEL',
    defaultValue: 'exampleNewsChannel',
  );

  /// Unique each tap so Telegram actually sends `/start ac_…` instead of opening a stale /start chat.
  static String mainBotAppCodeUrl(String startPayload) {
    return 'https://t.me/$mainBotUsername?start=$startPayload';
  }

  static const _bakedOpenSubtitlesKey = String.fromEnvironment('OPENSUBTITLES_API_KEY');

  /// Free OpenSubtitles **consumer** key (app, not a user login). Anonymous download quota is
  /// 5/day per IP. Empty skips that translate fallback.
  static String get openSubtitlesApiKey {
    if (_bakedOpenSubtitlesKey.trim().isNotEmpty) return _bakedOpenSubtitlesKey.trim();
    if (_allowEnvHandles) return SushiDotenv.get('OPENSUBTITLES_API_KEY').trim();
    return '';
  }
}
