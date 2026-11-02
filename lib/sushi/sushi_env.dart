import 'package:fladder/sushi/sushi_dotenv.dart';
import 'package:fladder/sushi/sushi_config.dart';

/// Build-time and runtime env for the Sushi client.
abstract final class SushiEnv {
  /// True when Sushi's Telegram-native backend is configured. Sushi has no HTTP/domain
  /// backend — everything goes over the Telegram bot API (see sushi_*_transport.dart) — so
  /// this reflects Telegram credentials, not any URL.
  static bool get isEnabled => telegramDirectPlayConfigured;

  static const String _cTelegramApiId = String.fromEnvironment('TELEGRAM_API_ID', defaultValue: '');
  static const String _cTelegramApiHash = String.fromEnvironment('TELEGRAM_API_HASH', defaultValue: '');
  static const String _cTelegramWebAppShortName =
      String.fromEnvironment('TELEGRAM_WEBAPP_SHORT_NAME', defaultValue: '');
  static const String _cTelegramHostedWebAppHttpsUrl =
      String.fromEnvironment('TELEGRAM_HOSTED_WEBAPP_HTTPS_URL', defaultValue: '');
  static const String _cTelegramWebAppBotUsername =
      String.fromEnvironment('TELEGRAM_WEBAPP_BOT_USERNAME', defaultValue: '');

  static String _pick(List<String> keys, String define) {
    final d = define.trim();
    if (d.isNotEmpty) return d;
    for (final k in keys) {
      final v = SushiDotenv.get(k).trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String? get botUsername {
    final h = SushiConfig.mainBotUsername;
    return h.isEmpty ? null : h;
  }

  static String? get telegramBotOpenLink {
    final b = botUsername;
    return b == null ? null : 'https://telegram.me/$b';
  }

  /// Deep link for self-service account delete in the main bot.
  static String? get telegramBotDeleteAccountLink {
    final b = botUsername;
    return b == null ? null : 'https://telegram.me/$b?start=delete_account';
  }

  static int? get telegramApiId {
    final t = _pick(['TELEGRAM_API_ID'], _cTelegramApiId);
    return t.isEmpty ? null : int.tryParse(t);
  }

  static String? get telegramApiHash {
    final t = _pick(['TELEGRAM_API_HASH'], _cTelegramApiHash);
    return t.isEmpty ? null : t;
  }

  static bool get telegramDirectPlayConfigured => telegramApiId != null && telegramApiHash != null;

  static String? get telegramWebAppShortName {
    final t = _pick(['TELEGRAM_WEBAPP_SHORT_NAME'], _cTelegramWebAppShortName);
    return t.isEmpty ? null : t;
  }

  static String? get telegramHostedWebAppHttpsUrl {
    final t = _pick(['TELEGRAM_HOSTED_WEBAPP_HTTPS_URL'], _cTelegramHostedWebAppHttpsUrl);
    return t.isEmpty ? null : t;
  }

  static String? get telegramWebAppBotUsername {
    final t = _pick(['TELEGRAM_WEBAPP_BOT_USERNAME'], _cTelegramWebAppBotUsername)
        .replaceFirst(RegExp(r'^@'), '');
    return t.isEmpty ? botUsername : t;
  }
}
