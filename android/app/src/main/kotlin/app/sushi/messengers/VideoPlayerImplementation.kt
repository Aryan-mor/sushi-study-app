package app.sushi.messengers

import PlaybackState
import PlayableData
import SubtitleSettings
import TVGuideModel
import VideoPlayerApi
import android.net.Uri
import android.util.Log
import android.os.Handler
import android.os.Looper
import androidx.core.net.toUri
import androidx.core.os.postDelayed
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import app.sushi.objects.PlayerSettingsObject
import app.sushi.objects.TdlibBridgeObject
import app.sushi.objects.SushiSubtitleSource
import app.sushi.objects.VideoPlayerObject
import app.sushi.utility.clearAudioTrack
import app.sushi.utility.clearSubtitleTrack
import app.sushi.utility.enableSubtitles
import app.sushi.utility.getAudioTracks
import app.sushi.utility.getSubtitleTracks
import app.sushi.utility.isInternalSubtitleTrackSelected
import app.sushi.utility.isSubtitleTrackDisabled
import app.sushi.utility.setInternalAudioTrack
import app.sushi.utility.setInternalSubtitleTrack
import kotlin.time.Duration.Companion.seconds

private const val OX_NATIVE_PLY_TAG = "OX_NATIVE_PLY"
private const val OX_STREAM_TAG = "OX_STREAM"
private const val OX_AUDIO_TAG = "OX_AUDIO"
const val SUSHI_EXT_SUB_ID = "sushi-ext"

private fun oxAudioLog(message: String) {
    Log.i(OX_AUDIO_TAG, message)
    Log.d(OX_NATIVE_PLY_TAG, message)
}

/**
 * Temporary: tracing the "plays ~1s, flashes black, continues" bug on start. Filter with
 * `adb logcat -s SUSHI_BLACK flutter`. Every ExoPlayer reset (stop/setMediaItem/prepare) and the
 * first rendered frame land here, with elapsedRealtime so Kotlin and Dart lines can be ordered.
 */
const val SUSHI_BLACK_TAG = "SUSHI_BLACK"

fun sushiBlackLog(message: String) {
    Log.i(SUSHI_BLACK_TAG, "t=${android.os.SystemClock.elapsedRealtime()} $message")
}

fun sushiBlackExoState(exo: ExoPlayer?): String {
    if (exo == null) return "exo=null"
    val state = when (exo.playbackState) {
        Player.STATE_IDLE -> "IDLE"
        Player.STATE_BUFFERING -> "BUFFERING"
        Player.STATE_READY -> "READY"
        Player.STATE_ENDED -> "ENDED"
        else -> "?"
    }
    return "exo=${System.identityHashCode(exo)} state=$state items=${exo.mediaItemCount} " +
        "isPlaying=${exo.isPlaying} pwr=${exo.playWhenReady} posMs=${exo.currentPosition}"
}

private fun oxStreamLog(message: String) {
    Log.i(OX_STREAM_TAG, message)
    Log.d(OX_NATIVE_PLY_TAG, message)
}

/**
 * The synthetic playback-session id inside a Telegram-sourced url, or null for anything else.
 *
 * Both transports put it in the last path segment: `tdlib-file://{fileId}` (ExoPlayer's
 * OxRoutingDataSource) and `http://127.0.0.1:{port}/{fileId}` (TdlibHttpBridgeServer). The scheme
 * and host are checked first so an ordinary media/subtitle url that happens to end in digits is
 * never mistaken for a session handle.
 */
private fun telegramPlaybackFileId(url: String?): Int? {
    if (url.isNullOrBlank()) return null
    val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return null
    val isTelegramTransport = uri.scheme == "tdlib-file" ||
        (uri.host == "127.0.0.1" || uri.host == "localhost")
    if (!isTelegramTransport) return null
    return url.substringAfterLast('/').toIntOrNull()
}

private fun redactStreamUrl(url: String): String {
    val uri = Uri.parse(url)
    val path = uri.encodedPath ?: uri.path ?: ""
    return "${uri.scheme}://${uri.host}$path?…"
}

class VideoPlayerImplementation(
) : VideoPlayerApi {
    var player: ExoPlayer? = null
    val playbackData: MutableStateFlow<PlayableData?> = MutableStateFlow(null)

    var subsInitialized = false

    /** Last known position when the activity went to background (survives activity recreation). */
    var savedPositionMs: Long = 0L

    /** Whether playback was active when the activity went to background. */
    var wasPlayingBeforeBackground: Boolean = false

    private var playbackErrorListener: Player.Listener? = null

    private val embeddedCueSeen = LinkedHashSet<String>()

    fun resetEmbeddedCueForward() {
        embeddedCueSeen.clear()
    }

    /** Forwards a handful of distinct muxed cues so Dart can tell Persian text from an `en` tag. */
    fun forwardEmbeddedCue(text: String?) {
        val cue = text?.trim().orEmpty()
        if (cue.isEmpty() || cue in embeddedCueSeen || embeddedCueSeen.size >= 8) return
        embeddedCueSeen.add(cue)
        VideoPlayerObject.videoPlayerListener?.onEmbeddedSubtitleCue(cue) {}
    }

    private var initialPositionLogPosted = false

    private fun scheduleInitialPositionLog(exo: ExoPlayer, requestedStartMs: Long) {
        if (initialPositionLogPosted) return
        initialPositionLogPosted = true
        val checkpoints = longArrayOf(3_000L, 12_000L, 30_000L)
        for (delayMs in checkpoints) {
            Handler(Looper.getMainLooper()).postDelayed({
                if (exo.mediaItemCount == 0) return@postDelayed
                val state = when (exo.playbackState) {
                    Player.STATE_IDLE -> "IDLE"
                    Player.STATE_BUFFERING -> "BUFFERING"
                    Player.STATE_READY -> "READY"
                    Player.STATE_ENDED -> "ENDED"
                    else -> "?"
                }
                oxStreamLog(
                    "phase=native_position_check delayMs=$delayMs state=$state " +
                        "requestedStartMs=$requestedStartMs actualMs=${exo.currentPosition} " +
                        "bufferedMs=${exo.bufferedPosition} durationMs=${exo.duration}",
                )
            }, delayMs)
        }
    }

    /** When [open] runs before ExoPlayer is bound, retry with this URL after [init]. */
    private var pendingOpenUrl: String? = null
    private var pendingOpenPlay: Boolean = true

    /**
     * Telegram playback-session id this player actually opened, or null.
     *
     * Recorded at the moment [open] commits a url to ExoPlayer — deliberately NOT read back out of
     * [playbackData] at teardown time. playbackData is replaced by sendPlayableModel as soon as the
     * NEXT playback is prepared, which on the next-episode path happens before the previous
     * player's teardown runs: reading it there identified the incoming session as the one that had
     * ended and released it, leaving the starting playback with no byte pipe (observed as a
     * next-episode that never opened). This field only ever names a session this player opened, so
     * a late teardown cannot reach a newer one.
     */
    private var openedTelegramFileId: Int? = null

    fun saveBackgroundState() {
        val exo = player ?: return
        val pos = exo.currentPosition.coerceAtLeast(0L)
        if (pos > 0L) {
            savedPositionMs = pos
            playbackData.value = playbackData.value?.copy(startPosition = pos)
        }
        wasPlayingBeforeBackground = exo.isPlaying || exo.playWhenReady
    }

    fun restoreAfterBackground() {
        val exo = player ?: return
        if (exo.mediaItemCount == 0) return

        val resumeMs = savedPositionMs
        if (resumeMs > 0L && kotlin.math.abs(exo.currentPosition - resumeMs) > 500L) {
            sushiBlackLog("restoreAfterBackground SEEK resumeMs=$resumeMs ${sushiBlackExoState(exo)}")
            exo.seekTo(resumeMs)
        }
        if (wasPlayingBeforeBackground && !exo.isPlaying) {
            exo.play()
        }
        publishPlaybackState(exo)
    }

    /**
     * Ends the current playback session: drops [playbackData] and releases any Telegram byte pipe.
     *
     * Three callers, all legitimate: Dart's Pigeon `stop()`, MainActivity's activity-result hook,
     * and ExoPlayer's onDispose when the Activity is finishing. The recurring hazard is not any one
     * of them but their *timing* — a teardown belonging to the outgoing item arriving after the
     * incoming one is already in place, at which point this wipes the new playback instead of the
     * old one. It has happened twice, and both times the symptom pointed somewhere else entirely:
     *
     *  - a stale url read here released the incoming Telegram session (fixed by [openedTelegramFileId])
     *  - audio_service's onNotificationDeleted called stop() ~1.5s into the next episode, which
     *    nulled playbackData and left the native player with no title and prev/next drawn at
     *    CustomButton's disabled alpha of 0.15 — indistinguishable from missing buttons
     *    (fixed in MediaControlsWrapper.onNotificationDeleted)
     *
     * So when playback data disappears mid-session, suspect a late teardown before suspecting the
     * UI. Logging `playbackData.value?.currentItem?.id` here names the victim immediately: if it is
     * the item that just STARTED rather than the one that ended, that is the bug.
     */
    fun clearSession(finalPositionMs: Long? = null, finalDurationMs: Long? = null) {
        // Use the id this player opened with, not whatever url playbackData holds now — see
        // [openedTelegramFileId]. Consuming it here also makes repeat teardowns (ExoPlayer dispose,
        // then MainActivity, then Dart's stop) no-ops rather than three attempts to release.
        val endedFileId = openedTelegramFileId
        openedTelegramFileId = null
        playbackData.value = null

        // Belt-and-suspenders: this runs on every teardown path (Dart's stop(), MainActivity's
        // activity-result hook, ExoPlayer's onDispose), unlike the onStop() Pigeon call from
        // Compose's onDispose, which has been observed to silently not reach Dart on at least one
        // real device (no crash, no log — just nothing). Prefer the position/duration this caller
        // captured live from ExoPlayer; fall back to savedPositionMs (set on backgrounding) only
        // when the caller had no live player reference left.
        val reportPositionMs = finalPositionMs ?: savedPositionMs
        val controls = VideoPlayerObject.videoPlayerControls
        Log.d(
            "SUSHI_PROGRESS",
            "clearSession finalPositionMs=$finalPositionMs savedPositionMs=$savedPositionMs " +
                "reportPositionMs=$reportPositionMs finalDurationMs=$finalDurationMs " +
                "controlsIsNull=${controls == null}",
        )
        if (reportPositionMs > 0L) {
            controls?.onPlaybackClosed(
                reportPositionMs,
                finalDurationMs ?: 0L,
                callback = { result ->
                    Log.d("SUSHI_PROGRESS", "onPlaybackClosed callback result=$result")
                },
            )
        }

        savedPositionMs = 0L
        wasPlayingBeforeBackground = false
        pendingOpenUrl = null
        initialPositionLogPosted = false
        // No-op unless this session's video actually came from Telegram — see doc there.
        TdlibBridgeObject.onTelegramPlaybackEnded(endedFileId)
    }

    private fun publishPlaybackState(exo: ExoPlayer) {
        val hasMedia = exo.mediaItemCount > 0
        val state = exo.playbackState
        VideoPlayerObject.setPlaybackState(
            PlaybackState(
                position = exo.currentPosition,
                buffered = exo.bufferedPosition,
                duration = exo.duration,
                playing = exo.isPlaying,
                buffering = state == Player.STATE_BUFFERING,
                completed = state == Player.STATE_ENDED,
                failed = state == Player.STATE_IDLE && !hasMedia,
            ),
        )
    }

    val isTVMode: Flow<Boolean> = playbackData.asStateFlow().map {
        it?.mediaInfo?.playbackType == PlaybackType.TV
    }

    override fun sendPlayableModel(
        playableData: PlayableData,
        callback: (Result<Boolean>) -> Unit
    ) {
        try {
            Log.d(
                OX_NATIVE_PLY_TAG,
                "sendPlayableModel title=${playableData.currentItem?.title} id=${playableData.currentItem?.id} " +
                    "playbackType=${playableData.mediaInfo.playbackType} startMs=${playableData.startPosition} " +
                    "urlLen=${playableData.url.length} audioTracks=${playableData.audioTracks.size} " +
                    "subtitleTracks=${playableData.subtitleTracks.size}",
            )
            oxStreamLog(
                "phase=native_playable itemId=${playableData.currentItem?.id} " +
                    "startMs=${playableData.startPosition} " +
                    "host=${Uri.parse(playableData.url).host} " +
                    "url=${redactStreamUrl(playableData.url)}",
            )
            // This is the only writer of a whole [playbackData], and everything the native UI shows
            // — title, chapters, segments, and the prev/next buttons via nextVideo/previousVideo —
            // hangs off it. When that UI has looked wrong, the value written here was always
            // correct and something cleared it afterwards; logging nextVideo/previousVideo on the
            // line above is what proved that, and is worth re-adding for a day if it recurs.
            // See [clearSession].
            playbackData.value = playableData
            resetEmbeddedCueForward()
            savedPositionMs = playableData.startPosition.coerceAtLeast(0L)
            callback(Result.success(true))
            return
        } catch (e: Exception) {
            Log.e(OX_NATIVE_PLY_TAG, "sendPlayableModel failed", e)
            callback(Result.success(false))
            return
        }
    }

    override fun sendTVGuideModel(guide: TVGuideModel, callback: (Result<Boolean>) -> Unit) {
        try {
            VideoPlayerObject.tvGuide.value = guide
            callback(Result.success(true))
        } catch (e: Exception) {
            println("Error sending TV guide model: $e")
            callback(Result.success(false))
        }
    }

    override fun setSubtitleSettings(settings: SubtitleSettings) {
        try {
            PlayerSettingsObject.subtitleSettings.value = settings
        } catch (e: Exception) {
            println("Error setting subtitle settings: $e")
        }
    }

    override fun refreshDefaultTrackSelection(callback: (Result<Boolean>) -> Unit) {
        Handler(Looper.getMainLooper()).post {
            try {
                val data = playbackData.value
                val exo = player
                if (data == null || exo == null) {
                    callback(Result.success(false))
                    return@post
                }
                VideoPlayerObject.setAudioTrackIndex(data.defaultAudioTrack.toInt(), true)
                VideoPlayerObject.setSubtitleTrackIndex(data.defaultSubtrack.toInt(), true)
                exo.properlySetSubAndAudioTracks(data)
                callback(Result.success(true))
            } catch (e: Exception) {
                println("Error refreshDefaultTrackSelection $e")
                callback(Result.success(false))
            }
        }
    }

    private var sushiExtFile: java.io.File? = null
    var pendingSelectSushiExt = false
    var sushiExtLanguage: String? = null

    override fun setSubtitleFromText(
        data: String,
        title: String?,
        languageCode: String?,
        callback: (Result<Boolean>) -> Unit,
    ) {
        Handler(Looper.getMainLooper()).post {
            try {
                callback(Result.success(sideloadSushiSubtitle(data, title, languageCode)))
            } catch (e: Exception) {
                Log.e(OX_NATIVE_PLY_TAG, "setSubtitleFromText", e)
                callback(Result.success(false))
            }
        }
    }

    override fun setEmbeddedSubtitleLanguage(index: Long, languageCode: String) {
        val label = if (languageCode.equals("fa", ignoreCase = true)) "FA" else languageCode.uppercase()
        val data = playbackData.value
        if (data != null) {
            playbackData.value = data.copy(
                subtitleTracks = data.subtitleTracks.map { track ->
                    if (track.index == index) track.copy(name = label, languageCode = languageCode) else track
                },
            )
        }
        VideoPlayerObject.usePersianSubtitleFace =
            languageCode.equals("fa", ignoreCase = true) ||
                languageCode.equals("per", ignoreCase = true) ||
                languageCode.equals("fas", ignoreCase = true)
    }

    override fun clearExternalSubtitle(callback: (Result<Boolean>) -> Unit) {
        Handler(Looper.getMainLooper()).post {
            try {
                callback(Result.success(clearSushiExternalSubtitle()))
            } catch (e: Exception) {
                Log.e(OX_NATIVE_PLY_TAG, "clearExternalSubtitle", e)
                callback(Result.success(false))
            }
        }
    }

    private fun sideloadSushiSubtitle(data: String, title: String?, languageCode: String?): Boolean {
        val exo = player
        if (exo == null) {
            Log.w(OX_NATIVE_PLY_TAG, "sideload skip: exo null chars=${data.length}")
            return false
        }
        val activity = VideoPlayerObject.currentActivity
        if (activity == null) {
            Log.w(OX_NATIVE_PLY_TAG, "sideload skip: no activity chars=${data.length}")
            return false
        }
        if (data.isBlank()) return false
        val file = java.io.File(activity.cacheDir, "sushi_ext_sub.srt")
        file.writeText(data, Charsets.UTF_8)
        sushiExtFile = file
        sushiExtLanguage = languageCode
        pendingSelectSushiExt = true
        val armed = VideoPlayerObject.armedSushiSubtitleSource
        VideoPlayerObject.armedSushiSubtitleSource = SushiSubtitleSource.None
        VideoPlayerObject.sushiSubtitleSource.value = when {
            armed != SushiSubtitleSource.None -> armed
            (title ?: "").startsWith("AI ") -> SushiSubtitleSource.Ai
            else -> SushiSubtitleSource.Automatic
        }
        VideoPlayerObject.sushiExternalSubtitleActive.value = true
        val current = exo.currentMediaItem
        if (current == null) {
            Log.w(OX_NATIVE_PLY_TAG, "sideload skip: no media item chars=${data.length}")
            return false
        }
        val pos = exo.currentPosition.coerceAtLeast(0L)
        val play = exo.playWhenReady
        sushiBlackLog("REPREPARE sideloadSushiSubtitle chars=${data.length} lang=$languageCode ${sushiBlackExoState(exo)}")
        val kept = (current.localConfiguration?.subtitleConfigurations ?: emptyList())
            .filter { it.id != SUSHI_EXT_SUB_ID }
        val sidecar = MediaItem.SubtitleConfiguration.Builder(android.net.Uri.fromFile(file))
            .setId(SUSHI_EXT_SUB_ID)
            .setMimeType(MimeTypes.APPLICATION_SUBRIP)
            .setLanguage(languageCode ?: "fa")
            .setLabel(title ?: "Online")
            .setSelectionFlags(androidx.media3.common.C.SELECTION_FLAG_DEFAULT)
            .build()
        val rebuilt = current.buildUpon()
            .setSubtitleConfigurations(kept + sidecar)
            .build()
        exo.setMediaItem(rebuilt, pos)
        exo.prepare()
        exo.playWhenReady = play
        VideoPlayerObject.usePersianSubtitleFace = languageCode.equals("fa", ignoreCase = true) ||
            languageCode.equals("per", ignoreCase = true)
        Log.d(
            OX_NATIVE_PLY_TAG,
            "sideload ok chars=${data.length} lang=$languageCode title=$title pos=$pos",
        )
        return true
    }

    private fun clearSushiExternalSubtitle(): Boolean {
        val exo = player ?: return false
        val current = exo.currentMediaItem ?: return true
        val kept = (current.localConfiguration?.subtitleConfigurations ?: emptyList())
            .filter { it.id != SUSHI_EXT_SUB_ID }
        if (kept.size == (current.localConfiguration?.subtitleConfigurations?.size ?: 0)) return true
        pendingSelectSushiExt = false
        VideoPlayerObject.sushiExternalSubtitleActive.value = false
        sushiExtFile = null
        val pos = exo.currentPosition.coerceAtLeast(0L)
        val play = exo.playWhenReady
        sushiBlackLog("REPREPARE clearSushiExternalSubtitle ${sushiBlackExoState(exo)}")
        exo.setMediaItem(current.buildUpon().setSubtitleConfigurations(kept).build(), pos)
        exo.prepare()
        exo.playWhenReady = play
        VideoPlayerObject.usePersianSubtitleFace = false
        return true
    }

    private var openSeq = 0

    override fun open(url: String, play: Boolean, callback: (Result<Boolean>) -> Unit) =
        openInternal(url, play, "dart", callback)

    private fun openInternal(url: String, play: Boolean, source: String, callback: (Result<Boolean>) -> Unit) {
        val seq = ++openSeq
        sushiBlackLog(
            "open scheduled seq=$seq source=$source play=$play urlLen=${url.length} " +
                "pendingOpenUrl=${pendingOpenUrl != null} ${sushiBlackExoState(player)}",
        )
        Handler(Looper.getMainLooper()).postDelayed(delayInMillis = 1.seconds.inWholeMilliseconds) {
            try {
                val exo = player
                sushiBlackLog(
                    "open run seq=$seq source=$source latestSeq=$openSeq play=$play " +
                        sushiBlackExoState(exo) +
                        (if (exo != null && exo.mediaItemCount > 0) " <-- RESETS ALREADY-LOADED MEDIA" else ""),
                )
                if (exo == null) {
                    Log.w(
                        OX_NATIVE_PLY_TAG,
                        "open defer: ExoPlayer not ready yet (will retry when host is bound)",
                    )
                    pendingOpenUrl = url
                    pendingOpenPlay = play
                    callback(Result.success(false))
                    return@postDelayed
                }
                pendingOpenUrl = null
                val pd = playbackData.value
                Log.d(
                    OX_NATIVE_PLY_TAG,
                    "open enter play=$play urlLen=${url.length} hasPlaybackData=${pd != null} " +
                        "exoPlayerNull=false",
                )
                pd?.let {
                    VideoPlayerObject.setAudioTrackIndex(it.defaultAudioTrack.toInt(), true)
                    VideoPlayerObject.setSubtitleTrackIndex(it.defaultSubtrack.toInt(), true)
                }

                val isHls = url.contains("streamMode=hls", ignoreCase = true) || url.endsWith(
                    ".m3u8",
                    ignoreCase = true
                )
                val subTitles = playbackData.value?.subtitleTracks ?: listOf()
                val externalSubs = subTitles.filter { it.external && !it.url.isNullOrEmpty() }
                Log.d(
                    OX_NATIVE_PLY_TAG,
                    "open building MediaItem isHls=$isHls externalSubtitleCount=${externalSubs.size} " +
                        "startPositionMs=${playbackData.value?.startPosition ?: 0L}",
                )
                val mediaItemBuilder = MediaItem.Builder()
                    .setUri(url)
                    .setTag(playbackData.value?.currentItem?.title)
                    .setMediaId(playbackData.value?.currentItem?.id ?: "")
                    .setSubtitleConfigurations(
                        subTitles.filter { it.external && !it.url.isNullOrEmpty() }.map { sub ->
                            MediaItem.SubtitleConfiguration.Builder(sub.url!!.toUri())
                                .setMimeType(guessSubtitleMimeType(sub.url))
                                .setLanguage(sub.languageCode)
                                .setLabel(sub.name)
                                .build()
                        }
                    )

                if (isHls) {
                    mediaItemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
                }

                val mediaItem = mediaItemBuilder.build()

                val startPosition = (playbackData.value?.startPosition ?: 0L).coerceAtLeast(0L)

                sushiBlackLog("open reset seq=$seq source=$source stop+clear+setMediaItem startMs=$startPosition")
                exo.stop()
                exo.clearMediaItems()

                // The commit point: from here this player owns that Telegram session, and its
                // teardown — and only its teardown — may release it.
                openedTelegramFileId = telegramPlaybackFileId(url)

                exo.setMediaItem(mediaItem, startPosition)
                exo.prepare()
                exo.playWhenReady = play
                oxStreamLog(
                    "phase=native_open startMs=$startPosition " +
                        "host=${Uri.parse(url).host} isHls=$isHls url=${redactStreamUrl(url)}",
                )
                Log.d(OX_NATIVE_PLY_TAG, "open prepared playWhenReady=$play startPositionMs=$startPosition")
                callback(Result.success(true))
                subsInitialized = false
                scheduleInitialPositionLog(exo, startPosition)
                return@postDelayed
            } catch (e: Exception) {
                Log.e(OX_NATIVE_PLY_TAG, "open exception", e)
                callback(Result.success(false))
                return@postDelayed
            }
        }
    }

    override fun setLooping(looping: Boolean) {
        player?.repeatMode = if (looping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
    }

    override fun setVolume(volume: Double) {
        val exo = player
        val applied = volume.toFloat().coerceIn(0f, 1f)
        oxAudioLog(
            "phase=audio_set_volume requested=$volume applied=$applied exoNull=${exo == null}",
        )
        exo?.volume = applied
    }

    override fun setPlaybackSpeed(speed: Double) {
        player?.setPlaybackSpeed(speed.toFloat())
    }

    override fun play() {
        player?.play()
    }

    override fun pause() {
        player?.pause()
    }

    override fun seekTo(position: Long) {
        sushiBlackLog("seekTo(dart) ms=$position ${sushiBlackExoState(player)}")
        player?.seekTo(position)
    }

    override fun stop() {
        val exo = player
        sushiBlackLog("stop(dart) ${sushiBlackExoState(exo)}")
        val finalPositionMs = exo?.currentPosition?.coerceAtLeast(0L)
        val finalDurationMs = exo?.duration?.takeIf { it > 0L }
        exo?.stop()
        exo?.clearMediaItems()
        clearSession(finalPositionMs, finalDurationMs)
    }

    fun init(exoPlayer: ExoPlayer?) {
        sushiBlackLog(
            "init newExo=${exoPlayer?.let { System.identityHashCode(it) }} " +
                "old=${sushiBlackExoState(player)} pendingOpenUrl=${pendingOpenUrl != null} " +
                "hasPlaybackData=${playbackData.value != null} savedPositionMs=$savedPositionMs " +
                "wasPlaying=$wasPlayingBeforeBackground",
        )
        playbackErrorListener?.let { player?.removeListener(it) }
        playbackErrorListener = null
        player = exoPlayer
        subsInitialized = false
        if (exoPlayer == null) {
            pendingOpenUrl = null
            return
        }
        val errorListener = object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                Log.e(
                    OX_NATIVE_PLY_TAG,
                    "onPlayerError code=${error.errorCode} name=${error.errorCodeName} " +
                        "msg=${error.message} cause=${error.cause?.message}",
                    error,
                )
                VideoPlayerObject.reportPlaybackError(error)
            }
        }
        playbackErrorListener = errorListener
        exoPlayer.addListener(errorListener)
        val deferredUrl = pendingOpenUrl
        val deferredPlay = pendingOpenPlay
        if (!deferredUrl.isNullOrBlank()) {
            pendingOpenUrl = null
            Log.d(OX_NATIVE_PLY_TAG, "init applying deferred open urlLen=${deferredUrl.length} play=$deferredPlay")
            openInternal(deferredUrl, deferredPlay, "init_deferred", callback = {})
            return
        }
        playbackData.value?.let { playData ->
            if (exoPlayer.mediaItemCount > 0) {
                sushiBlackLog("init branch=restoreAfterBackground")
                restoreAfterBackground()
                return
            }
            val resumeMs = savedPositionMs.takeIf { it > 0L } ?: playData.startPosition
            val updated = playData.copy(startPosition = resumeMs)
            playbackData.value = updated
            VideoPlayerObject.setAudioTrackIndex(updated.defaultAudioTrack.toInt(), true)
            VideoPlayerObject.setSubtitleTrackIndex(updated.defaultSubtrack.toInt(), true)
            val shouldPlay = wasPlayingBeforeBackground
            Log.d(
                OX_NATIVE_PLY_TAG,
                "init restoring after recreation resumeMs=$resumeMs play=$shouldPlay",
            )
            sushiBlackLog("init branch=restore_open resumeMs=$resumeMs play=$shouldPlay")
            openInternal(updated.url, shouldPlay, "init_restore", callback = {})
        }
    }

    /** Only clears the binding when the releasing instance is still current (activity switch race). */
    fun releasePlayer(exoPlayer: ExoPlayer): Boolean {
        if (player !== exoPlayer) return false
        playbackErrorListener?.let { exoPlayer.removeListener(it) }
        playbackErrorListener = null
        player = null
        subsInitialized = false
        return true
    }
}

fun guessSubtitleMimeType(fileName: String): String = when {
    fileName.contains(".srt", ignoreCase = true) -> MimeTypes.APPLICATION_SUBRIP
    fileName.contains(".vtt", ignoreCase = true) -> MimeTypes.TEXT_VTT
    fileName.contains(".ass", ignoreCase = true) -> MimeTypes.TEXT_SSA
    else -> MimeTypes.APPLICATION_SUBRIP
}

fun ExoPlayer.properlySetSubAndAudioTracks(playableData: PlayableData) {
    if (playableData.mediaInfo.playbackType == PlaybackType.TV) {
        // In TV mode, do not set tracks here as they are handled differently
        return
    }
    val exo = this
    try {
        // User picks in native UI update current*Index + playbackData; prefer that over stale defaults.
        val currentSubIndex = VideoPlayerObject.currentSubtitleTrackIndex.value.toLong()
        val internalSubTracks = this.getSubtitleTracks()
        val selectedSushiExt = VideoPlayerObject.implementation.pendingSelectSushiExt && internalSubTracks.isNotEmpty()
        if (selectedSushiExt) {
            val sushi = internalSubTracks.lastOrNull {
                it.language.equals("fa", ignoreCase = true) ||
                    it.label.contains("Online", ignoreCase = true) ||
                    it.label.contains("AI Persian", ignoreCase = true) ||
                    it.label.contains("auto", ignoreCase = true)
            } ?: internalSubTracks.last()
            VideoPlayerObject.implementation.pendingSelectSushiExt = false
            VideoPlayerObject.sushiExternalSubtitleActive.value = true
            Log.d(
                OX_NATIVE_PLY_TAG,
                "select sushi ext label=${sushi.label} lang=${sushi.language} tracks=${internalSubTracks.size}",
            )
            clearSubtitleTrack()
            Handler(Looper.getMainLooper()).post {
                try {
                    exo.setInternalSubtitleTrack(sushi)
                } catch (_: Exception) {
                }
            }
        } else if (VideoPlayerObject.sushiExternalSubtitleActive.value) {
            // A Sushi auto/online subtitle is the active track; currentSubtitleTrackIndex still
            // holds the stale pre-Automatic server default, so letting the block below run on a
            // later onTracksChanged (seek/buffer/TV resume) would silently revert the selection.
        } else {
        val listPos = playableData.subtitleTracks.indexOfFirst { it.index == currentSubIndex }
        val wantedSubIndex: Int = when {
            listPos >= 0 -> listPos - 1
            currentSubIndex > 0 &&
                internalSubTracks.isNotEmpty() &&
                listPos < 0 -> {
                0
            }
            else -> listPos - 1
        }

        if (wantedSubIndex < 0) {
            if (!exo.isSubtitleTrackDisabled()) {
                clearSubtitleTrack()
            }
        } else if (wantedSubIndex >= internalSubTracks.size) {
            // Exo text tracks not mapped yet; a later onTracksChanged will schedule again.
        } else {
            val subTrack = internalSubTracks[wantedSubIndex]
            if (!exo.isInternalSubtitleTrackSelected(subTrack)) {
                // Do not clear first. clear disables the text renderer, the follow-up select
                // then no-ops on the unmapped groups, and a few Off/On toggles stick on Off.
                Handler(Looper.getMainLooper()).post {
                    try {
                        exo.setInternalSubtitleTrack(subTrack)
                    } catch (_: Exception) {
                    }
                }
            }
            val serverLang = playableData.subtitleTracks
                .firstOrNull { it.index == currentSubIndex }
                ?.languageCode
                ?.lowercase()
            VideoPlayerObject.usePersianSubtitleFace = serverLang == "fa" ||
                serverLang == "per" ||
                serverLang == "fas" ||
                serverLang == "pes"
        }
        }

        val currentAudioIndex = VideoPlayerObject.currentAudioTrackIndex.value.toLong()
        val indexOfAudioTrack =
            playableData.audioTracks.indexOfFirst { it.index == currentAudioIndex }
        val internalAudioTracks = this.getAudioTracks()

        val wantedAudioIndex = indexOfAudioTrack - 1
        // playableData.audioTracks[0] is the Jellyfin "Off" row; real streams start at index 1.
        fun serverIndexForInternal(internalIdx: Int) {
            // A negative index is the "Off" sentinel — Sushi titles with no per-track metadata
            // send every audio stream as index -1 (see sushiBuildMediaStreams). Persisting that
            // back as the selected track makes the next onTracksChanged pass hit
            // "disable_audio_negative_index" and mute a stream that is actually playing, so only
            // remember a real, mapped server index here. The fallback stays idempotent: the
            // selected index is left alone and we simply re-select the same Exo track next pass.
            playableData.audioTracks.getOrNull(internalIdx + 1)?.index?.let {
                if (it >= 0) VideoPlayerObject.setAudioTrackIndex(it.toInt(), true)
            }
        }
        val action = when {
            internalAudioTracks.isEmpty() -> "clear_empty_exo_tracks"
            currentAudioIndex < 0 -> "disable_audio_negative_index"
            wantedAudioIndex < 0 -> "fallback_first_exo_track"
            wantedAudioIndex >= internalAudioTracks.size -> "fallback_last_exo_track"
            else -> "select_mapped_exo_track"
        }
        oxAudioLog(
            "phase=audio_track_apply action=$action currentAudioIndex=$currentAudioIndex " +
                "wantedAudioIndex=$wantedAudioIndex exoAudioCount=${internalAudioTracks.size} " +
                "pigeonAudioCount=${playableData.audioTracks.size} defaultAudio=${playableData.defaultAudioTrack} " +
                "exoCodecs=${internalAudioTracks.joinToString { it.codec ?: "?" }}",
        )
        if (internalAudioTracks.isEmpty()) {
            clearAudioTrack()
        } else if (currentAudioIndex < 0) {
            clearAudioTrack(disable = true)
        } else if (wantedAudioIndex < 0) {
            // Jellyfin stream index not in pigeon list — fall back to first mapped Exo track.
            clearAudioTrack(false)
            setInternalAudioTrack(internalAudioTracks[0])
            serverIndexForInternal(0)
        } else if (wantedAudioIndex >= internalAudioTracks.size) {
            clearAudioTrack(false)
            setInternalAudioTrack(internalAudioTracks[internalAudioTracks.lastIndex])
            serverIndexForInternal(internalAudioTracks.lastIndex)
        } else {
            clearAudioTrack(false)
            setInternalAudioTrack(internalAudioTracks[wantedAudioIndex])
            serverIndexForInternal(wantedAudioIndex)
        }
    } catch (e: Exception) {
        e.printStackTrace()
    }
}
