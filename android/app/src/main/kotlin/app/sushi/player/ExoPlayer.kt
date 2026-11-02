package app.sushi.player

import PlaybackState
import android.app.ActivityManager
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.view.WindowManager
import androidx.activity.compose.LocalActivity
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.displayCutoutPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.getSystemService
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.ts.TsExtractor
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import android.util.Log
import io.github.peerless2012.ass.media.kt.buildWithAssSupport
import io.github.peerless2012.ass.media.type.AssRenderType
import kotlinx.coroutines.delay

import app.sushi.composables.overlays.guide.GuideOverlay
import app.sushi.composables.overlays.NextUpOverlay
import app.sushi.messengers.properlySetSubAndAudioTracks
import app.sushi.messengers.sushiBlackExoState
import app.sushi.messengers.sushiBlackLog
import app.sushi.objects.PlayerSettingsObject
import app.sushi.objects.VideoPlayerObject
import app.sushi.utility.AllowedOrientations
import app.sushi.utility.conditional
import app.sushi.utility.getAudioTracks
import app.sushi.utility.getSubtitleTracks
import app.sushi.utility.setInternalSubtitleTrack
import app.sushi.utility.leanBackEnabled
import kotlin.time.Duration.Companion.seconds

private const val OX_NATIVE_PLY_TAG = "OX_NATIVE_PLY"

val LocalPlayer = compositionLocalOf<ExoPlayer?> { null }

@OptIn(UnstableApi::class)
@Composable
internal fun ExoPlayer(
    controls: @Composable (
        player: ExoPlayer,
    ) -> Unit,
) {
    val videoHost = VideoPlayerObject
    val context = LocalContext.current
    val activityManager = context.getSystemService<ActivityManager>()
    val isLowRamDevice = activityManager?.isLowRamDevice == true
    val isLeanBackTv = leanBackEnabled(context)
    val conserveMemory = isLowRamDevice || isLeanBackTv

    val extractorsFactory = DefaultExtractorsFactory().apply {
        setTsExtractorTimestampSearchBytes(
            when (isLowRamDevice) {
                true -> TsExtractor.TS_PACKET_SIZE * 1800
                false -> TsExtractor.DEFAULT_TIMESTAMP_SEARCH_BYTES
            }
        )
        // CBR as fallback only (MP3/AAC without seek tables). AlwaysEnabled forces estimated
        // byte offsets even when MKV cues exist — mid-element seeks → "No valid varint length
        // mask found" and playback stops on Telegram tdlib-file:// progressive MKV.
        setConstantBitrateSeekingEnabled(true)
        setConstantBitrateSeekingAlwaysEnabled(false)
    }

    val dataSourceFactory = remember {
        // Video comes from the user's own TDLib session (tdlib-file:// URIs) — no server byte
        // relay in this build. The HTTP branch here only ever serves subtitle delivery from the
        // OX API, never video, so no ox-stream-specific auth header is needed.
        val httpFactory = DefaultDataSource.Factory(context, DefaultHttpDataSource.Factory())
        OxRoutingDataSource.Factory(httpFactory)
    }

    val audioAttributes = AudioAttributes.Builder()
        .setUsage(C.USAGE_MEDIA)
        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
        .build()

    val renderersFactory = DefaultRenderersFactory(context)
        .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
        .setEnableDecoderFallback(true)

    val trackSelector = DefaultTrackSelector(context).apply {
        setParameters(buildUponParameters().apply {
            if (!conserveMemory) {
                setAudioOffloadPreferences(
                    TrackSelectionParameters.AudioOffloadPreferences.DEFAULT.buildUpon().apply {
                        setAudioOffloadMode(TrackSelectionParameters.AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_ENABLED)
                    }.build()
                )
            }
            setTunnelingEnabled(PlayerSettingsObject.settings.value?.enableTunneling ?: false)
            setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)
        })
    }

    // Fladder TV: Media3 DefaultLoadControl (~50s). OX 15–45s / 16MB caused
    // mid-playback rebuffers on leanback; keep reduced buffer only for phone low-RAM.
    val loadControl = if (isLowRamDevice && !isLeanBackTv) {
        DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                15_000,
                45_000,
                1_500,
                3_000,
            )
            .setTargetBufferBytes(16 * 1024 * 1024)
            .build()
    } else {
        DefaultLoadControl.Builder().build()
    }

    val trackApplyHandler = remember { Handler(Looper.getMainLooper()) }
    var pendingTrackApply by remember { mutableStateOf<Runnable?>(null) }

    val exoPlayer = remember {
        ExoPlayer.Builder(context, renderersFactory)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory, extractorsFactory))
            .setAudioAttributes(audioAttributes, true)
            .setHandleAudioBecomingNoisy(true)
            .setPauseAtEndOfMediaItems(true)
            .setVideoScalingMode(C.VIDEO_SCALING_MODE_SCALE_TO_FIT)
            .buildWithAssSupport(
                context,
                renderersFactory = renderersFactory,
                extractorsFactory = extractorsFactory,
                // Without this, buildWithAssSupport builds its own internal MediaSource pipeline
                // (needed to wrap ASS subtitle rendering around playback) using ITS OWN default
                // DataSource.Factory instead of the OxRoutingDataSource one set two lines up via
                // .setMediaSourceFactory(...) — silently discarding tdlib-file:// routing, so
                // ExoPlayer tries to open it as a plain HTTP URL and fails with
                // "MalformedURLException: unknown protocol: tdlib-file". Confirmed via javap on
                // ass-media 0.3.0's compiled AssPlayerKt: dataSourceFactory is a real (optional,
                // defaulted) parameter here, just never wired up before this fix.
                dataSourceFactory = dataSourceFactory,
                renderType = AssRenderType.LEGACY
            )
    }

    fun updatePlaybackState() {
        val bound = VideoPlayerObject.implementation.player
        // A superseded activity (player left on the back stack under a second
        // VideoPlayerActivity) must not publish. Both loops write the same
        // StateFlow, so play/pause flips every time the zombie reports.
        if (bound != null && bound !== exoPlayer) return
        val hasMedia = exoPlayer.mediaItemCount > 0
        val state = exoPlayer.playbackState
        videoHost.setPlaybackState(
            PlaybackState(
                position = exoPlayer.currentPosition,
                buffered = exoPlayer.bufferedPosition,
                duration = exoPlayer.duration,
                playing = exoPlayer.isPlaying,
                buffering = state == Player.STATE_BUFFERING,
                completed = state == Player.STATE_ENDED,
                failed = state == Player.STATE_IDLE && !hasMedia,
            )
        )
    }

    LaunchedEffect(exoPlayer) {
        while (true) {
            updatePlaybackState()
            delay(1.seconds)
        }
    }

    val activity = LocalActivity.current

    DisposableEffect(exoPlayer) {
        val listener = object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                Log.e(
                    OX_NATIVE_PLY_TAG,
                    "onPlayerError code=${error.errorCode} name=${error.errorCodeName} " +
                        "msg=${error.message} cause=${error.cause?.message}",
                    error,
                )
                VideoPlayerObject.reportPlaybackError(error)
                super.onPlayerError(error)
            }

            override fun onRenderedFirstFrame() {
                sushiBlackLog("listener onRenderedFirstFrame ${sushiBlackExoState(exoPlayer)}")
            }

            override fun onMediaItemTransition(mediaItem: androidx.media3.common.MediaItem?, reason: Int) {
                sushiBlackLog("listener onMediaItemTransition reason=$reason id=${mediaItem?.mediaId}")
            }

            override fun onTimelineChanged(timeline: androidx.media3.common.Timeline, reason: Int) {
                sushiBlackLog("listener onTimelineChanged reason=$reason empty=${timeline.isEmpty}")
            }

            override fun onPositionDiscontinuity(
                oldPosition: Player.PositionInfo,
                newPosition: Player.PositionInfo,
                reason: Int,
            ) {
                sushiBlackLog(
                    "listener onPositionDiscontinuity reason=$reason " +
                        "oldMs=${oldPosition.positionMs} newMs=${newPosition.positionMs}",
                )
            }

            override fun onVideoSizeChanged(videoSize: androidx.media3.common.VideoSize) {
                sushiBlackLog("listener onVideoSizeChanged ${videoSize.width}x${videoSize.height}")
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                sushiBlackLog("listener onIsPlayingChanged isPlaying=$isPlaying ${sushiBlackExoState(exoPlayer)}")
                activity?.window?.let {
                    if (isPlaying) {
                        it.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        it.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                }
                super.onIsPlayingChanged(isPlaying)
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                sushiBlackLog("listener onPlaybackStateChanged ${sushiBlackExoState(exoPlayer)}")
                updatePlaybackState()
            }

            override fun onEvents(player: Player, events: Player.Events) {
                super.onEvents(player, events)
                updatePlaybackState()
            }

            override fun onCues(cueGroup: CueGroup) {
                val impl = VideoPlayerObject.implementation
                for (cue in cueGroup.cues) {
                    impl.forwardEmbeddedCue(cue.text?.toString())
                }
            }

            override fun onTracksChanged(tracks: Tracks) {
                super.onTracksChanged(tracks)
                val subTracks = exoPlayer.getSubtitleTracks()
                val audioTracks = exoPlayer.getAudioTracks()

                Log.i(
                    "OX_AUDIO",
                    "phase=audio_tracks_changed exoAudio=${audioTracks.size} exoSub=${subTracks.size} " +
                        "exoVolume=${exoPlayer.volume} playing=${exoPlayer.isPlaying} " +
                        "audioCodecs=${audioTracks.joinToString { it.codec ?: "?" }}",
                )

                if (subTracks.isEmpty() && audioTracks.isEmpty()) return

                // Always publish Exo track lists so UI (e.g. hasSubtracks) matches the player.
                // Exo can fire onTracksChanged first with audio-only, then again when embedded
                // text tracks appear; the old logic set subsInitialized on the first callback and
                // never refreshed exoSubTracks, so subtitles stayed hidden until a later session.
                val hadNoExoAudioTracks = VideoPlayerObject.exoAudioTracks.value.isEmpty()
                val hadNoExoSubtitleTracks = VideoPlayerObject.exoSubTracks.value.isEmpty()
                VideoPlayerObject.exoSubTracks.value = subTracks
                VideoPlayerObject.exoAudioTracks.value = audioTracks
                val pendingSub = VideoPlayerObject.pendingInternalSubtitle
                if (pendingSub != null && subTracks.isNotEmpty()) {
                    VideoPlayerObject.pendingInternalSubtitle = null
                    trackApplyHandler.post {
                        exoPlayer.setInternalSubtitleTrack(pendingSub)
                    }
                }

                val impl = VideoPlayerObject.implementation
                // Short deferral: track groups must be mapped before overrides stick; debounce
                // so rapid onTracksChanged bursts (e.g. after TV Home resume) coalesce to one apply.
                val scheduleApplyDefaults: () -> Unit = scheduleApplyDefaults@{
                    val playbackData = impl.playbackData.value ?: return@scheduleApplyDefaults
                    pendingTrackApply?.let { trackApplyHandler.removeCallbacks(it) }
                    val runnable = Runnable {
                        pendingTrackApply = null
                        sushiBlackLog("trackApply properlySetSubAndAudioTracks ${sushiBlackExoState(exoPlayer)}")
                        exoPlayer.properlySetSubAndAudioTracks(playbackData)
                    }
                    pendingTrackApply = runnable
                    trackApplyHandler.postDelayed(runnable, 150)
                }

                if (!impl.subsInitialized) {
                    impl.subsInitialized = true
                    scheduleApplyDefaults()
                } else if ((hadNoExoSubtitleTracks && subTracks.isNotEmpty()) ||
                    (hadNoExoAudioTracks && audioTracks.isNotEmpty()) ||
                    impl.pendingSelectSushiExt
                ) {
                    // Late-mapped text or audio tracks after the initial snapshot, or a
                    // sideloaded AI/online subtitle (sideloadSushiSubtitle) still waiting to be
                    // selected. sideloadSushiSubtitle's setMediaItem()+prepare() re-maps every
                    // track and fires this callback again with audio/sub already non-empty, so
                    // without this branch scheduleApplyDefaults() never runs: the pending
                    // subtitle selection is silently dropped and the previously-chosen audio
                    // track's override is never reasserted against the freshly remapped groups.
                    scheduleApplyDefaults()
                }
            }
        }
        exoPlayer.addListener(listener)
        onDispose {
            pendingTrackApply?.let { trackApplyHandler.removeCallbacks(it) }
            pendingTrackApply = null
            exoPlayer.removeListener(listener)
        }
    }

    DisposableEffect(Unit) {
        VideoPlayerObject.implementation.init(exoPlayer)
        onDispose {
            val finishing = activity?.isFinishing == true
            val superseded = VideoPlayerObject.currentActivity != null &&
                VideoPlayerObject.currentActivity !== activity
            sushiBlackLog(
                "compose onDispose finishing=$finishing superseded=$superseded ${sushiBlackExoState(exoPlayer)}",
            )
            Log.d("SUSHI_PROGRESS", "ExoPlayer onDispose finishing=$finishing superseded=$superseded")
            if (superseded) {
                VideoPlayerObject.implementation.releasePlayer(exoPlayer)
            } else if (finishing) {
                // Capture position/duration from the still-live ExoPlayer instance before
                // releasePlayer() nulls out the implementation's reference to it — clearSession()
                // reports these to Dart as a reliable fallback in case onStop() below doesn't land.
                val finalPositionMs = exoPlayer.currentPosition.coerceAtLeast(0L)
                val finalDurationMs = exoPlayer.duration.takeIf { it > 0L }
                Log.d("SUSHI_PROGRESS", "ExoPlayer onDispose captured finalPositionMs=$finalPositionMs finalDurationMs=$finalDurationMs")
                videoHost.videoPlayerControls?.onStop(callback = {})
                if (VideoPlayerObject.implementation.releasePlayer(exoPlayer)) {
                    VideoPlayerObject.implementation.clearSession(finalPositionMs, finalDurationMs)
                    VideoPlayerObject.tvGuide.value = null
                }
            } else {
                // Activity recreated (e.g. TV home) — keep session data for restore in init().
                VideoPlayerObject.implementation.saveBackgroundState()
                VideoPlayerObject.implementation.releasePlayer(exoPlayer)
            }
            exoPlayer.release()
        }
    }

    val acceptedOrientations by PlayerSettingsObject.acceptedOrientations.collectAsState(emptyList())
    val fillScreen by PlayerSettingsObject.fillScreen.collectAsState(false)
    val videoFit by PlayerSettingsObject.videoFit.collectAsState(AspectRatioFrameLayout.RESIZE_MODE_FIT)

    val isTVPlayback by VideoPlayerObject.implementation.isTVMode.collectAsState(false)
    val nativeSubtitleSettings by PlayerSettingsObject.subtitleSettings.collectAsState(null)

    @Composable
    fun createPlayer(showControls: Boolean) {
        var playerView by remember { mutableStateOf<PlayerView?>(null) }
        val lifecycleOwner = LocalLifecycleOwner.current

        DisposableEffect(lifecycleOwner, playerView) {
            val view = playerView
            if (view == null) {
                onDispose { }
            } else {
                val observer = LifecycleEventObserver { _, event ->
                    when (event) {
                        Lifecycle.Event.ON_RESUME -> view.onResume()
                        Lifecycle.Event.ON_PAUSE -> view.onPause()
                        else -> Unit
                    }
                }
                lifecycleOwner.lifecycle.addObserver(observer)
                onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
            }
        }

        AndroidView(
            modifier = Modifier
                .fillMaxSize()
                .background(color = Color.Black)
                .conditional(!fillScreen) {
                    displayCutoutPadding()
                },
            factory = {
                PlayerView(it).apply {
                    player = exoPlayer
                    useController = false
                    resizeMode = videoFit
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    )
                    keepScreenOn = false
                    playerView = this
                    subtitleView?.apply {
                        setStyle(
                            CaptionStyleCompat(
                                android.graphics.Color.WHITE,
                                android.graphics.Color.TRANSPARENT,
                                android.graphics.Color.TRANSPARENT,
                                CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                                android.graphics.Color.BLACK,
                                null
                            )
                        )
                    }
                }
            },
            update = { view ->
                nativeSubtitleSettings?.let { subtitleSettings ->
                    view.subtitleView?.apply {
                        setApplyEmbeddedFontSizes(false)

                        val frac =
                            (subtitleSettings.fontSize / 1080.0).toFloat().coerceIn(0.01f, 1f)
                        setFractionalTextSize(frac)

                        setBottomPaddingFraction(
                            subtitleSettings.verticalOffset.toFloat().coerceIn(0f, 0.5f)
                        )

                        setStyle(
                            CaptionStyleCompat(
                                subtitleSettings.color.toInt(),
                                subtitleSettings.backgroundColor.toInt(),
                                android.graphics.Color.TRANSPARENT,
                                CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                                subtitleSettings.outlineColor.toInt(),
                                persianSubtitleTypeface(view.context)
                                    ?: if (subtitleSettings.fontWeight >= 700) android.graphics.Typeface.DEFAULT_BOLD else android.graphics.Typeface.DEFAULT
                            )
                        )
                    }
                }
            },
        )
        if (showControls)
            CompositionLocalProvider(LocalPlayer provides exoPlayer) {
                controls(exoPlayer)
            }
    }

    AllowedOrientations(
        acceptedOrientations
    ) {
        when (isTVPlayback) {
            true -> GuideOverlay(
                modifier = Modifier.fillMaxSize(),
                overlay = {
                    createPlayer(showControls = it)
                }
            )

            false -> NextUpOverlay(
                modifier = Modifier
                    .fillMaxSize(),
                overlay = {
                    createPlayer(showControls = it)
                },
            )
        }
    }
}

private var cachedPersianFace: android.graphics.Typeface? = null

private fun persianSubtitleTypeface(context: android.content.Context): android.graphics.Typeface? {
    if (!app.sushi.objects.VideoPlayerObject.usePersianSubtitleFace) return null
    cachedPersianFace?.let { return it }
    val paths = listOf(
        "flutter_assets/assets/fonts/vazirmatn/Vazirmatn-Regular.ttf",
        "assets/fonts/vazirmatn/Vazirmatn-Regular.ttf",
    )
    for (path in paths) {
        try {
            cachedPersianFace = android.graphics.Typeface.createFromAsset(context.assets, path)
            return cachedPersianFace
        } catch (_: Exception) {
        }
    }
    return null
}

