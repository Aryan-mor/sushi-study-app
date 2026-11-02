/// No-op on platforms without JS interop (mobile, desktop native).
abstract final class SushiHlsWebBufferConfig {
  static Future<void> apply() async {}
}
