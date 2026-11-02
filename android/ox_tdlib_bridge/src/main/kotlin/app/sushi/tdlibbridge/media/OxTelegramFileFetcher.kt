package app.sushi.tdlibbridge.media

import app.sushi.tdlibbridge.session.GomobileCallGate
import mobile.PlaybackSession

/**
 * Replaces TdApi.File's local.path/local.downloadOffset/local.downloadedPrefixSize/
 * local.isDownloadingCompleted/size fields with the gotd/td-facade equivalent shape.
 * windowStart/windowEnd bound the single current contiguous downloaded region — same "resets on
 * a non-adjacent seek" semantics as TDLib's downloadOffset/downloadedPrefixSize (see
 * DownloadSession's doc in go/oxtelegram/download.go).
 */
data class OxFileInfo(
    val localPath: String,
    val size: Long,
    val windowStart: Long,
    val windowEnd: Long,
    val isDownloadingCompleted: Boolean,
)

/**
 * Adapts one resolved mobile.PlaybackSession (gomobile-bound github.com/gotd/td facade) to
 * TdlibFileFetcher's calling shape, so TelegramFileDataSource/TdlibHttpBridgeServer only need a
 * constructor type swap, not a rewrite, when replacing TDLib.
 *
 * Unlike TDLib's fetcher (one instance shared across potentially many files by fileId), this
 * wraps exactly one gotd/td PlaybackSession, matching this module's one-playback-session-at-a-
 * time scope (see TdlibBridgeObject) — the fileId parameters below are accepted (so call sites
 * don't need to change) but not consulted against [session].
 *
 * Every [session] call below goes through [GomobileCallGate] — confirmed live that [close] racing
 * an unrelated Sushi protocol call (itself a [app.sushi.tdlibbridge.session.OxTelegramClient]
 * call) crashes the whole process with `fatal error: bulkBarrierPreWrite: unaligned arguments`,
 * since both cross into the same gomobile-bound oxtelegram.aar runtime. [awaitBytesAvailable] and
 * [cancelDownload] are included too: TdlibBridgeObject's own doc notes a new session's start and
 * the previous one's teardown are explicitly not ordered, so the same overlap is possible here.
 */
class OxTelegramFileFetcher(private val session: PlaybackSession) {

    /**
     * No-op: unlike TDLib's DownloadFile (a separate "start background download" call before
     * polling progress), this facade's [awaitBytesAvailable] both starts and waits in one call.
     * Kept as a real suspend function so call sites (which call this before awaitBytesAvailable,
     * mirroring TDLib's shape) don't need restructuring.
     */
    @Suppress("UNUSED_PARAMETER")
    suspend fun requestDownload(fileId: Int, offset: Long, limit: Long = 0, priority: Int = 32) {
    }

    suspend fun awaitBytesAvailable(fileId: Int, offset: Long, minBytesAvailable: Long): OxFileInfo =
        GomobileCallGate.enter("awaitBytes") {
            session.ensureAvailable(offset, minBytesAvailable)
            OxFileInfo(
                localPath = session.localPath(),
                size = session.size(),
                windowStart = session.availableFrom(),
                windowEnd = session.availableUpTo(),
                isDownloadingCompleted = session.isComplete(),
            )
        }

    /**
     * Cancels whatever chunk fetch is currently in flight for this session — call on every
     * DataSource.close()/connection teardown, including mid-seek, not just final playback end.
     * See DownloadSession's cancellation doc: a leak here reproduces the exact class of
     * resource-exhaustion bug already found once this session on the TDLib side, just on the Go
     * side of the gomobile boundary instead.
     */
    @Suppress("UNUSED_PARAMETER")
    suspend fun cancelDownload(fileId: Int) {
        GomobileCallGate.enter { session.cancelCurrentRead() }
    }

    /**
     * Releases the underlying session's resources for good — migrated-DC connection and cache file
     * handle (see PlaybackSession.Close in go/oxtelegram/mobile/bind.go). Unlike [cancelDownload],
     * which only aborts in-flight chunk fetches and is called on every seek, this ends the session:
     * call it exactly once, when the playback it belongs to is finished.
     *
     * The on-disk .part file deliberately survives, so replaying the same title resumes from what
     * was already downloaded instead of refetching from byte zero.
     */
    suspend fun close() {
        GomobileCallGate.enter("closeSession") { session.close() }
    }
}
