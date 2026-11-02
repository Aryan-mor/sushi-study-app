import 'package:fladder/src/tdlib_bridge.g.dart';

/// Web/stub — Windows gotd host unavailable.
bool sushiTelegramUseWindowsHost() => false;

class SushiTelegramWindowsBridge {
  SushiTelegramWindowsBridge({void Function(SushiTdlibAuthState state)? onAuthStateChanged});

  SushiTdlibAuthState get state =>
      SushiTdlibAuthState(kind: SushiTdlibAuthStateKind.uninitialized);

  Future<bool> hasPersistedSessionFile() async => false;

  Future<void> configure(int apiId, String apiHash) async {
    throw UnsupportedError('oxtelegram Windows host not available on this platform');
  }

  SushiTdlibAuthState currentAuthState() => state;
  bool isNativeSessionBot() => false;

  Future<void> submitPhoneNumber(String phone) async => throw UnsupportedError('windows-only');
  Future<void> submitBotToken(String token) async => throw UnsupportedError('windows-only');
  Future<void> submitCode(String code) async => throw UnsupportedError('windows-only');
  Future<void> submitTwoFactorPassword(String password) async =>
      throw UnsupportedError('windows-only');
  Future<void> requestQrLogin() async => throw UnsupportedError('windows-only');
  Future<void> logOut() async => throw UnsupportedError('windows-only');
  Future<String> startPlaybackSession(SushiTdlibPlaybackSource source) async =>
      throw UnsupportedError('windows-only');
  Future<void> stopPlaybackSession(String sessionUri) async =>
      throw UnsupportedError('windows-only');
  Future<void> warmDelivery(SushiTdlibPlaybackSource source) async =>
      throw UnsupportedError('windows-only');
  Future<void> ensureProviderBotsReady(List<SushiTdlibProviderBot> bots) async =>
      throw UnsupportedError('windows-only');
  // The next three are silent no-ops rather than throws: callers treat "nothing armed / no id" as a
  // normal outcome, and this file is only ever reached on a platform where the Windows host isn't
  // the active bridge anyway.
  void armDeliveryWaiter(String locator) {}
  SushiTdlibDeliveryRef? deliveryRefForLocator(String locator) => null;
  Future<String> fetchWebAppInitData(
    String botUsername,
    String? webAppShortName,
    String? hostedHttpsUrl,
  ) async =>
      throw UnsupportedError('windows-only');

  Future<String> sendTextAndWaitReply(String username, String text, int timeoutMs) async =>
      throw UnsupportedError('windows-only');

  Future<String> fetchSmallDocument(int botId, int messageId, String locator, int timeoutMs) async =>
      throw UnsupportedError('windows-only');

  Future<void> fetchDocumentThumb(int providerBotId, int messageId, String locator, String outPath, int timeoutMs) async =>
      throw UnsupportedError('windows-only');
}
