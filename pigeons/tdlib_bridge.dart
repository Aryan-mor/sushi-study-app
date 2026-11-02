import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/tdlib_bridge.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/app/src/main/kotlin/app/sushi/api/TdlibBridge.g.kt',
    kotlinOptions: KotlinOptions(
      includeErrorClass: false,
    ),
    dartPackageName: 'nl_jknaapen_fladder.tdlib_bridge',
  ),
)

/// Mirrors the subset of TdApi.AuthorizationState this module surfaces to Dart
/// (see app.sushi.tdlibbridge.auth.TdlibAuthState on the Kotlin side).
enum SushiTdlibAuthStateKind {
  uninitialized,
  waitingForPhoneNumber,
  waitingForCode,
  waitingForPassword,
  waitingForQrConfirmation,
  ready,
  loggingOut,
  closed,
  failed,
}

/// Liveness of the MTProto socket — deliberately a different question from [SushiTdlibAuthStateKind].
///
/// A device can hold perfectly valid credentials (auth `ready`) while its connection is dead, in
/// which case every byte fetch fails. Treating that as "logged out" is what sent TV users to a
/// login screen for something a silent reconnect fixes, so the two states are reported separately
/// and only [SushiTdlibAuthStateKind.failed] may ever drive a re-login prompt.
enum SushiTdlibConnectionHealth {
  /// configure() has not completed successfully yet.
  uninitialized,

  /// A connection attempt (first connect, or a reconnect) is in flight.
  connecting,

  /// Socket is live; RPCs and playback downloads can be issued.
  ready,

  /// Socket died while credentials remain valid. The native side is already retrying with
  /// backoff — surface it as a transient banner at most, never as a login prompt.
  degraded,
}

class SushiTdlibAuthState {
  final SushiTdlibAuthStateKind kind;
  // Set when kind == waitingForQrConfirmation: the tg:// login URL to render as a QR code.
  final String? qrLoginUrl;
  // Set when kind == waitingForPassword: TDLib's password hint for the account, if any.
  final String? passwordHint;
  // Set when kind == failed: human-readable message for the login UI.
  final String? errorMessage;

  const SushiTdlibAuthState({
    required this.kind,
    this.qrLoginUrl,
    this.passwordHint,
    this.errorMessage,
  });
}

/// One playback session's Telegram-backed video source, parsed from the PlaybackInfo Path
/// `sushi-tg://{providerBotId}/{messageId}?loc={locator}`.
class SushiTdlibPlaybackSource {
  /// The delivery bot whose DM holds the video. 0 on a cold play: the backend round-robins across
  /// senders and may fail over mid-request, so it does not commit to one until the copy lands —
  /// the native side then learns the real sender from the update that carries [locator].
  final int providerBotId;
  /// The message id inside that DM, or 0 when the backend has none remembered yet and a fresh copy
  /// is on its way (the native side then matches the live push by [locator] instead).
  final int messageId;
  /// True when the target player is mpv/mdk (no DataSource-style hook for a custom scheme) —
  /// returns a http://127.0.0.1:{port}/{fileId} url served by TdlibHttpBridgeServer instead of
  /// tdlib-file://{fileId}. False (default) keeps the existing ExoPlayer DataSource path.
  final bool preferHttpBridge;
  /// The ?loc= query param off the PlaybackInfo Path: the caption on the copied message,
  /// OXM_PREFIX_recordNo with no '#' (see apps/api's resolveTelegramDelivery). Unique per stored
  /// file, and it does two jobs: it picks out the live-pushed document that answers THIS request
  /// instead of whatever arrives next on the shared receive channel (confirmed a real bug without
  /// it — concurrent dashboard-slider prefetches could hand one item's video to a different item's
  /// player), and on the remembered path it verifies [messageId] still holds the expected file.
  /// Always present now — both login modes read out of a DM.
  final String locator;

  const SushiTdlibPlaybackSource({
    required this.providerBotId,
    required this.messageId,
    required this.locator,
    this.preferHttpBridge = false,
  });
}

/// One delivery sender, as published by the backend's GET /telegram/provider-bots. The username is
/// needed only for first contact (contacts.resolveUsername -> startBot); afterwards everything
/// addresses the bot by [id]. Tokens never reach the client.
class SushiTdlibProviderBot {
  final int id;
  final String username;

  const SushiTdlibProviderBot({required this.id, required this.username});
}

/// Where a delivered video actually landed, as observed by THIS session. Both halves can only come
/// from the receiving side: private-chat message ids are numbered per side, and the server
/// round-robins across senders so it does not know which one won.
class SushiTdlibDeliveryRef {
  final int messageId;
  final int providerBotId;

  const SushiTdlibDeliveryRef({required this.messageId, required this.providerBotId});
}

@HostApi()
abstract class SushiTdlibBridgeApi {
  /// Must be called once before any other method (idempotent) — starts the underlying
  /// TDLib client with [apiId]/[apiHash] from SushiEnv (this module's own user-session
  /// credentials, distinct from the bot-based OX login's credentials).
  @async
  void configure(int apiId, String apiHash);

  /// Current auth state; also pushed via SushiTdlibBridgeEvents.onAuthStateChanged.
  /// Synchronous — this just reads cached state, no TDLib round-trip.
  SushiTdlibAuthState currentAuthState();

  /// Whether the CURRENT session — including one restored from disk at configure(), which never
  /// calls submitBotToken this process — is a bot rather than a phone/QR user account.
  ///
  /// Ground truth from the native side, not derived client-side: the Dart bridge controller used
  /// to infer this purely from whether IT had called submitBotToken during this run, which is
  /// wrong the moment a previously-connected bot session is silently restored on a warm app start
  /// (the normal case on every launch after the first). That made a reader-sync mismatch check
  /// (backend now delivering to the account's linked Telegram session, native still holding a
  /// stale restored bot session) never fire, and playback hung waiting on a push that could never
  /// reach that bot's own inbox. Synchronous — an in-memory read on the Go side.
  bool isNativeSessionBot();

  /// Current socket liveness; also pushed via SushiTdlibBridgeEvents.onConnectionHealthChanged.
  /// Synchronous — an in-memory read on the Go side, no round-trip.
  SushiTdlibConnectionHealth connectionHealth();

  /// Rebuilds the connection if its run loop has died; a no-op when already healthy.
  ///
  /// The native side reconnects on its own with backoff, so this is only for the moments where
  /// waiting beats failing: app resume, and immediately before a playback download. Completes when
  /// the connection is usable, or fails if it could not be re-established.
  @async
  void reconnect();

  /// Kills and relaunches the whole app process (Android only).
  ///
  /// A stuck/failed native TDLib client can land in a state a plain in-memory reconfigure cannot
  /// clear: go/oxtelegram/client.go's Configure() no-ops on "already have a live client object",
  /// even one whose auth landed in `failed` — only a client object that never existed rebuilds
  /// cleanly from the on-disk session. Killing the process is the only way to guarantee that from
  /// here, since there is no "drop this client but keep the session file" call exposed yet (see
  /// sushi_login_screen.dart's stuck-state UI). Session storage on disk is untouched, so the
  /// relaunched process resumes the same signed-in session — this is not a logout.
  ///
  /// Never returns (the process exits); the return type exists only so Dart can await the call
  /// being dispatched before the platform channel itself goes away.
  @async
  void restartApp();

  /// Phone/tablet flow, step 1. Async: waits on the real TdApi round-trip.
  @async
  void submitPhoneNumber(String phoneNumber);

  /// Phone/tablet flow, step 2.
  @async
  void submitCode(String code);

  /// Phone/tablet flow, step 3 — only valid when state is waitingForPassword.
  @async
  void submitTwoFactorPassword(String password);

  /// Android TV flow: request a QR login token; UI renders the URL pushed via
  /// onAuthStateChanged(waitingForQrConfirmation) as a QR code.
  @async
  void requestQrLogin();

  /// Bot-token login: an alternative to phone/QR for users who don't want to give Sushi
  /// access to their personal Telegram account. Logs in as a bot (gotd/td
  /// auth.importBotAuthorization) instead — goes straight to ready, no code/2FA step.
  @async
  void submitBotToken(String token);

  /// Server-side session invalidation + local TDLib session wipe.
  @async
  void logOut();

  /// Resolves [source] and starts downloading via TDLib, returning either a
  /// tdlib-file://{fileId} uri (ExoPlayer DataSource path) or, when
  /// source.preferHttpBridge is true, a http://127.0.0.1:{port}/{fileId} uri served by
  /// TdlibHttpBridgeServer (mpv/mdk path — see that class for why).
  /// Throws if no MTProto/TDLib session is logged in yet — callers should
  /// check currentAuthState() first and prompt login if not ready.
  @async
  String startPlaybackSession(SushiTdlibPlaybackSource source);

  /// Where the last successful resolve of [locator] landed, or null if this session has not read
  /// one. Dart reports it to the backend (POST /me/telegram-delivery) so the NEXT play of the same
  /// file is answered straight from the delivery table with no Telegram copy at all.
  ///
  /// It has to come from here rather than from the server: copyMessage hands the SENDING bot an id
  /// from its own side of the private chat, and private-chat ids are numbered per side, so only
  /// the receiving session ever sees the id that can be re-read later — and only it knows which
  /// sender the backend's round-robin actually settled on.
  /// Synchronous — reads an in-memory map, no MTProto round-trip.
  SushiTdlibDeliveryRef? deliveryRefForLocator(String locator);

  /// Registers interest in [locator] BEFORE the PlaybackInfo call that triggers the copy, so a
  /// delivery that lands while that HTTP request is still in flight is captured rather than raced
  /// for. Idempotent, synchronous, no MTProto round-trip.
  void armDeliveryWaiter(String locator);

  /// Resolves [source] and remembers where it landed WITHOUT opening a download — the warm-up path.
  /// Scrolling the dashboard warms a dozen titles at once, and starting a dozen progressive
  /// downloads for videos nobody pressed play on would spend the user's data on bytes that get
  /// thrown away. Resolving is enough: it makes the backend remember the message id, so the
  /// eventual play needs no Telegram call at all.
  @async
  void warmDelivery(SushiTdlibPlaybackSource source);

  /// Starts, mutes and archives every delivery sender on this account, so delivery copies never
  /// land in the user's visible inbox. Called on every app enter (not just after login) because a
  /// sender can be added to the backend's list at any time.
  ///
  /// No-op for a bot-token login: a bot is not a user account, has no dialog list to archive, and
  /// its B2B DM was already opened by main-bot's /connectbot.
  @async
  void ensureProviderBotsReady(List<SushiTdlibProviderBot> bots);

  /// Stops the active playback session's download and closes the TDLib client (does not log
  /// out — the on-disk session persists, next play just reconnects). Callers on every backend
  /// (ExoPlayer's own hook is native-side via VideoPlayerImplementation.clearSession; mpv/mdk
  /// have no equivalent Activity-scoped teardown, so their wrapper must call this explicitly
  /// when a Telegram-sourced item finishes) — see TdlibBridgeObject.onTelegramPlaybackEnded.
  @async
  void stopPlaybackSession(String sessionUri);

  /// Fetches a Telegram-signed Mini App `initData` payload for [botUsername] via TDLib's
  /// GetWebAppLinkUrl/GetWebAppUrl/GetMainWebApp — requires a Ready auth state (real Telegram
  /// login already completed) and a Mini App configured on that bot via @BotFather. Exchange the
  /// result with the backend's POST /auth/telegram to obtain OX session tokens; see
  /// SushiTelegramAuthClient. [webAppShortName]/[hostedHttpsUrl] may be null/empty if unset —
  /// at least one working WebApp path must be configured on the bot for this to succeed.
  ///
  /// Returns the absolute path of a temp file holding the initData, not the payload itself.
  /// Caller data must not cross gomobile as a Go string. [sushiReadBridgeFile] reads and deletes it.
  @async
  String fetchWebAppInitData(String botUsername, String? webAppShortName, String? hostedHttpsUrl);

  /// DMs [username] with [text] and waits for the next private-chat reply starting with `!`
  /// (Sushi wire framing). Used for `/initbot <corr>` against init-bot. [timeoutMs] ≤ 0 → 30000.
  ///
  /// Returns the absolute path of a temp file holding the reply, not the reply bytes.
  /// A search body returned as a Go string aborted the next JNI call (`bulkBarrierPreWrite`).
  /// [sushiReadBridgeFile] reads and deletes the file.
  @async
  String sendTextAndWaitReply(String username, String text, int timeoutMs);

  /// Downloads a whole small document (subtitle file, doc 15 §7) copied into this session's
  /// own chat. Waits for a live push whose caption is [locator] and whose message this locator
  /// has not already materialized — packs share one caption, and [messageId] is the Bot API
  /// sender counter, not this session's MTProto id.
  ///
  /// Returns the absolute path of the file. The bytes are not a return value: a Go string of
  /// the body crosses gomobile's write barrier and aborts the process. The Dart wrapper reads
  /// the file and deletes it. [timeoutMs] ≤ 0 → 30000.
  @async
  String fetchSmallDocument(int botId, int messageId, String locator, int timeoutMs);

  /// Writes the thumbnail of the video delivered at [messageId] in this session's own chat to
  /// [outPath] (a personal video's card image, ADR 0037 §6). [messageId] is the receiver-side id
  /// the player already used. The bytes never cross the bridge; the caller reads [outPath].
  /// Fails when the document has no thumbnail — the card keeps its placeholder. [timeoutMs] ≤ 0 →
  /// 15000.
  @async
  void fetchDocumentThumb(int providerBotId, int messageId, String locator, String outPath, int timeoutMs);

  /// DMs [username] with [text] without waiting for a reply — the fire-and-forget half of the
  /// wire protocol, for a Sushi command whose reply the client does not read (`/ack`; a future
  /// best-effort watch-progress report). Returns once the message is sent; unlike
  /// [sendTextAndWaitReply] it never blocks on a server reply, so it cannot stall the caller
  /// waiting on one that is never coming.
  @async
  void sendTextFireAndForget(String username, String text);

  /// Clicks a session account through main-bot's onboarding conversation (language, quality,
  /// audio, then login) by pressing the first inline button offered at each step, so `/initbot`
  /// has a binding to read afterward without a human tapping through Telegram by hand. No-op for
  /// a bot-token login (no dialog list, no onboarding conversation to have). [timeoutMs] bounds
  /// the whole multi-step conversation, not one round trip; ≤ 0 → 90000.
  @async
  void ensureMainBotOnboarded(String username, int timeoutMs);
}

@FlutterApi()
abstract class SushiTdlibBridgeEvents {
  void onAuthStateChanged(SushiTdlibAuthState state);

  /// Pushed whenever socket liveness changes. Independent of onAuthStateChanged — see
  /// [SushiTdlibConnectionHealth] for why the two must not be collapsed into one signal.
  void onConnectionHealthChanged(SushiTdlibConnectionHealth health);
}
