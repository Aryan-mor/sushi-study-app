import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract final class SushiDotenv {
  static bool get isLoaded => dotenv.isInitialized;

  static Future<void> ensureLoaded() async {
    if (dotenv.isInitialized) return;
    for (final name in ['assets/env/default.env', 'packages/fladder/assets/env/default.env']) {
      try {
        final raw = await rootBundle.loadString(name);
        if (raw.trim().isNotEmpty) {
          dotenv.testLoad(fileInput: raw);
          return;
        }
      } catch (_) {}
    }
    await dotenv.load(fileName: 'assets/env/default.env', isOptional: true);
  }

  static String get(String key) => dotenv.isInitialized ? (dotenv.env[key] ?? '') : '';
}
