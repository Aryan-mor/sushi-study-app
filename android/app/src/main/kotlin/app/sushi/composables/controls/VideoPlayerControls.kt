package app.sushi.composables.controls

import android.util.Log
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.displayCutoutPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.key
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import io.github.rabehx.iconsax.Iconsax
import io.github.rabehx.iconsax.filled.AudioSquare
import io.github.rabehx.iconsax.filled.Backward
import io.github.rabehx.iconsax.filled.Check
import io.github.rabehx.iconsax.filled.Flash
import io.github.rabehx.iconsax.filled.Forward
import io.github.rabehx.iconsax.filled.Pause
import io.github.rabehx.iconsax.filled.Play
import io.github.rabehx.iconsax.filled.SliderVertical
import io.github.rabehx.iconsax.filled.Subtitle
import io.github.rabehx.iconsax.outline.CloseSquare
import io.github.rabehx.iconsax.outline.Refresh
import kotlinx.coroutines.delay
import app.sushi.composables.dialogs.AudioPicker
import app.sushi.composables.dialogs.ChapterSelectionSheet
import app.sushi.composables.dialogs.PlaybackSpeedPicker
import app.sushi.composables.dialogs.SubtitlePicker
import app.sushi.composables.dialogs.SushiAiKeyMissingSheet
import app.sushi.composables.dialogs.SushiOnlineSubtitleSheet
import app.sushi.composables.dialogs.SushiSubtitleBusyOverlay
import app.sushi.composables.dialogs.sushiTranslateErrorMessage
import app.sushi.composables.shared.CurrentTime
import app.sushi.objects.PlayerSettingsObject
import app.sushi.objects.SushiSubtitleSource
import app.sushi.objects.VideoPlayerObject
import app.sushi.utility.ImmersiveSystemBars
import app.sushi.utility.defaultSelected
import app.sushi.utility.keyEvent
import app.sushi.utility.leanBackEnabled
import app.sushi.utility.visible
import kotlin.time.Duration.Companion.seconds

private enum class SushiSubtitlePending { None, Auto, Translate }

@OptIn(UnstableApi::class)
@Composable
fun CustomVideoControls(
    exoPlayer: ExoPlayer,
) {
    var showControls by remember { mutableStateOf(false) }
    val lastInteraction = remember { mutableLongStateOf(System.currentTimeMillis()) }

    val showAudioDialog = remember { mutableStateOf(false) }
    val showSubDialog = remember { mutableStateOf(false) }
    var showOnlineSheet by remember { mutableStateOf(false) }
    var showAiKeySheet by remember { mutableStateOf(false) }
    var aiKeySheetMessage by remember { mutableStateOf<String?>(null) }
    var subtitleBusy by remember { mutableStateOf<String?>(null) }
    var pendingSubtitle by remember { mutableStateOf(SushiSubtitlePending.None) }
    var showChapterDialog by remember { mutableStateOf(false) }
    var showSpeedDialog by remember { mutableStateOf(false) }

    val interactionSource = remember { MutableInteractionSource() }

    val isTVMode by VideoPlayerObject.implementation.isTVMode.collectAsState(false)

    val activity = LocalActivity.current

    val buffering by VideoPlayerObject.buffering.collectAsState(true)
    val playing by VideoPlayerObject.playing.collectAsState(false)
    val controlsPadding = 32.dp

    ImmersiveSystemBars(isImmersive = !showControls)

    val bottomControlFocusRequester = remember { FocusRequester() }

    fun hideControls() {
        showControls = false
        bottomControlFocusRequester.requestFocus()
    }

    Log.d("SUSHI_PROGRESS", "VideoPlayerControls composed leanBackEnabled=${leanBackEnabled(LocalContext.current)} activity=$activity")

    fun cancelSubtitleLoad() {
        subtitleBusy = null
        VideoPlayerObject.armedSushiSubtitleSource = SushiSubtitleSource.None
        VideoPlayerObject.videoPlayerControls?.cancelSushiSubtitle { }
    }

    BackHandler(
        enabled = true
    ) {
        Log.d("SUSHI_PROGRESS", "BackHandler invoked showControls=$showControls")
        if (subtitleBusy != null) {
            cancelSubtitleLoad()
        } else if (showControls) {
            hideControls()
        } else {
            Log.d("SUSHI_PROGRESS", "BackHandler calling activity.finish()")
            activity?.finish()
        }
    }

    // Restart the hide timer whenever `lastInteraction` changes.
    LaunchedEffect(lastInteraction.longValue) {
        delay(5.seconds)
        hideControls()
    }

    fun updateLastInteraction() {
        showControls = true
        lastInteraction.longValue = System.currentTimeMillis()
    }

    val forwardSpeed by PlayerSettingsObject.forwardSpeed.collectAsState(30.seconds)
    val backwardSpeed by PlayerSettingsObject.backwardSpeed.collectAsState(15.seconds)

    val position by VideoPlayerObject.position.collectAsState(0L)
    val player = VideoPlayerObject.implementation.player
    val lastSeekInteraction = remember { mutableLongStateOf(System.currentTimeMillis()) }

    var currentSkipTime by remember { mutableLongStateOf(0L) }

    // Restart the multiplier
    LaunchedEffect(lastSeekInteraction.longValue) {
        delay(1.seconds)
        if (currentSkipTime == 0L) return@LaunchedEffect
        player?.seekTo(position + currentSkipTime)
        currentSkipTime = 0L
    }

    fun updateSeekInteraction() {
        lastSeekInteraction.longValue = System.currentTimeMillis()
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .focusable(enabled = false)
            .onFocusChanged { focusState ->
                if (focusState.hasFocus) {
                    bottomControlFocusRequester.requestFocus()
                }
            }
            .keyEvent { keyEvent: KeyEvent ->
                when (keyEvent.key) {
                    // Back is handled only by BackHandler (KEY_UP). Returning false here
                    // without side effects prevents KEY_DOWN from showing controls before
                    // BackHandler runs — otherwise one press hides controls instead of exiting.
                    Key.Back -> return@keyEvent false

                    Key.MediaStop, Key.X -> {
                        activity?.finish()
                        return@keyEvent true
                    }

                    Key.MediaPlay -> {
                        player?.play()
                        return@keyEvent true
                    }

                    Key.MediaPlayPause -> {
                        player?.let {
                            if (it.isPlaying) {
                                it.pause()
                                updateLastInteraction()
                            } else {
                                it.play()
                            }
                        }
                        return@keyEvent true

                    }

                    Key.MediaPause, Key.P -> {
                        player?.pause()
                        updateLastInteraction()
                        return@keyEvent true
                    }

                    Key.Escape, Key.ButtonB, Key.Backspace -> {
                        // Key.Back is intentionally excluded here: it is handled exclusively by
                        // BackHandler above (via the system onBackPressed/KEY_UP path). Including
                        // it here as well would cause a double-trigger — KEY_DOWN fires this
                        // branch, then KEY_UP fires BackHandler — resulting in a single remote
                        // press both hiding controls AND immediately finishing the activity.
                        if (subtitleBusy != null) {
                            cancelSubtitleLoad()
                            return@keyEvent true
                        }
                        if (showControls) {
                            hideControls()
                            return@keyEvent true
                        } else {
                            activity?.finish()
                            return@keyEvent true
                        }
                    }
                }

                if (!showControls && !isTVMode) {
                    when (keyEvent.key) {
                        Key.DirectionLeft -> {
                            currentSkipTime -= backwardSpeed.inWholeMilliseconds
                            updateSeekInteraction()
                            return@keyEvent true
                        }

                        Key.DirectionRight -> {
                            currentSkipTime += forwardSpeed.inWholeMilliseconds
                            updateSeekInteraction()
                            return@keyEvent true
                        }
                    }
                    bottomControlFocusRequester.requestFocus()
                    updateLastInteraction()
                    return@keyEvent true
                } else {
                    updateLastInteraction()
                    return@keyEvent false
                }
            }
            .clickable(
                indication = null,
                interactionSource = interactionSource,
            ) {
                showControls = !showControls
                if (showControls) lastInteraction.longValue = System.currentTimeMillis()
            },
        contentAlignment = Alignment.BottomCenter
    ) {
        Box(
            modifier = Modifier.visible(
                visible = showControls,
            )
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier
                    .fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .wrapContentHeight()
                        .background(
                            brush = Brush.linearGradient(
                                colors = listOf(
                                    Color.Black.copy(alpha = 0.90f),
                                    Color.Black.copy(alpha = 0f),
                                ),
                                start = Offset(0f, 0f),
                                end = Offset(0f, Float.POSITIVE_INFINITY)
                            ),
                        )
                        .safeContentPadding(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp, alignment = Alignment.Start)
                ) {
                    Column(
                        modifier = Modifier
                            .padding(controlsPadding)
                            .weight(1f),
                    ) {
                        Row(
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            val state by VideoPlayerObject.implementation.playbackData.collectAsState(
                                null
                            )
                            state?.let {
                                ItemHeader(
                                    modifier = Modifier
                                        .weight(1f),
                                    it
                                )
                            }
                            if (!leanBackEnabled(LocalContext.current)) {
                                IconButton(
                                    {
                                        Log.d("SUSHI_PROGRESS", "X close button tapped, activity=$activity isFinishing=${activity?.isFinishing}")
                                        activity?.finish()
                                        Log.d("SUSHI_PROGRESS", "activity.finish() returned, isFinishing=${activity?.isFinishing}")
                                    }
                                ) {
                                    Icon(
                                        Iconsax.Outline.CloseSquare,
                                        modifier = Modifier
                                            .size(42.dp)
                                            .focusable(false),
                                        contentDescription = "Close icon",
                                        tint = Color.White,
                                    )
                                }
                            } else {
                                CurrentTime()
                            }
                        }
                    }
                }
                Spacer(modifier = Modifier.weight(1f))
                // Progress Bar
                Column(
                    modifier = Modifier
                        .background(
                            brush = Brush.linearGradient(
                                colors = listOf(
                                    Color.Black.copy(alpha = 0f),
                                    Color.Black.copy(alpha = 0.9f),
                                ),
                                start = Offset(0f, 0f),
                                end = Offset(0f, Float.POSITIVE_INFINITY)
                            ),
                        )
                        .padding(horizontal = controlsPadding)
                        .displayCutoutPadding()
                        .padding(top = 8.dp, bottom = controlsPadding)
                ) {
                    ProgressBar(
                        modifier = Modifier,
                        exoPlayer, bottomControlFocusRequester, ::updateLastInteraction
                    )
                    Row(
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                    ) {
                        LeftButtons(
                            openChapterSelection = {
                                showChapterDialog = true
                            },
                            openPlaybackSpeedPicker = {
                                showSpeedDialog = true
                            }
                        )
                        PlaybackButtons(exoPlayer, bottomControlFocusRequester) {
                            updateLastInteraction()
                        }
                        RightButtons(showAudioDialog, showSubDialog)
                    }
                }
            }
        }
        SegmentSkipOverlay()
        SeekOverlay(value = currentSkipTime)
        if (buffering && !playing) {
            CircularProgressIndicator(
                modifier = Modifier
                    .align(alignment = Alignment.Center)
                    .size(64.dp),
                strokeCap = StrokeCap.Round,
                strokeWidth = 10.dp
            )
        }
    }

    if (showAudioDialog.value) {
        AudioPicker(
            player = exoPlayer,
            onDismissRequest = {
                showAudioDialog.value = false
            }
        )
    }

    if (showSubDialog.value) {
        SubtitlePicker(
            player = exoPlayer,
            onDismissRequest = {
                showSubDialog.value = false
            },
            onAutomatic = {
                if (subtitleBusy == null && pendingSubtitle == SushiSubtitlePending.None) {
                    pendingSubtitle = SushiSubtitlePending.Auto
                }
            },
            onOnline = {
                showOnlineSheet = true
            },
            onTranslate = {
                if (subtitleBusy == null && pendingSubtitle == SushiSubtitlePending.None) {
                    pendingSubtitle = SushiSubtitlePending.Translate
                }
            },
        )
    }

    // Key only the sheet close. Resetting pendingSubtitle must not cancel this effect.
    LaunchedEffect(showSubDialog.value) {
        if (showSubDialog.value) return@LaunchedEffect
        when (pendingSubtitle) {
            SushiSubtitlePending.None -> return@LaunchedEffect
            SushiSubtitlePending.Auto -> {
                pendingSubtitle = SushiSubtitlePending.None
                delay(400)
                hideControls()
                subtitleBusy = "Searching sub-plus…"
                VideoPlayerObject.videoPlayerControls?.autoLoadSushiSubtitle { result ->
                    val r = result.getOrNull()
                    if (r?.errorCode != "busy") {
                        subtitleBusy = null
                        if (r?.ok != true) {
                            VideoPlayerObject.armedSushiSubtitleSource = SushiSubtitleSource.None
                        }
                        if (r?.errorCode == "stale") return@autoLoadSushiSubtitle
                        hideControls()
                        val msg = when {
                            r == null -> "Could not load subtitle"
                            r.ok -> r.label ?: "Subtitle loaded"
                            r.errorCode == "no_results" -> "No subtitles found"
                            else -> "Could not load subtitle"
                        }
                        android.widget.Toast.makeText(
                            activity,
                            msg,
                            android.widget.Toast.LENGTH_SHORT,
                        ).show()
                    }
                }
            }
            SushiSubtitlePending.Translate -> {
                pendingSubtitle = SushiSubtitlePending.None
                delay(400)
                hideControls()
                subtitleBusy = "Translating…"
                VideoPlayerObject.videoPlayerControls?.translateSubtitleToPersian { result ->
                    val r = result.getOrNull()
                    if (r?.errorCode != "busy") {
                        subtitleBusy = null
                        if (r?.ok != true) {
                            VideoPlayerObject.armedSushiSubtitleSource = SushiSubtitleSource.None
                        }
                        if (r?.errorCode == "stale") return@translateSubtitleToPersian
                        hideControls()
                        when {
                            r == null -> android.widget.Toast.makeText(
                                activity, "Could not translate", android.widget.Toast.LENGTH_SHORT,
                            ).show()
                            r.ok -> android.widget.Toast.makeText(
                                activity, r.label ?: "Subtitle applied", android.widget.Toast.LENGTH_SHORT,
                            ).show()
                            r.errorCode == "missing_key" -> {
                                aiKeySheetMessage = null
                                showAiKeySheet = true
                            }
                            // Both cases are plausibly a bad/exhausted key — route to the same
                            // bot/QR sheet used for "no key yet" so the user can swap it in place,
                            // just with copy that explains this isn't a first-time setup.
                            r.errorCode == "translate_quota_exceeded" -> {
                                aiKeySheetMessage = sushiTranslateErrorMessage(r.errorCode)
                                showAiKeySheet = true
                            }
                            r.errorCode == "translate_service_failed" -> {
                                aiKeySheetMessage = sushiTranslateErrorMessage(r.errorCode)
                                showAiKeySheet = true
                            }
                            r.errorCode == "no_source" -> android.widget.Toast.makeText(
                                activity,
                                "Need a text subtitle first — try Online subtitles",
                                android.widget.Toast.LENGTH_SHORT,
                            ).show()
                            else -> android.widget.Toast.makeText(
                                activity, "Could not translate", android.widget.Toast.LENGTH_SHORT,
                            ).show()
                        }
                    }
                }
            }
        }
    }

    if (showOnlineSheet) {
        SushiOnlineSubtitleSheet(onDismissRequest = {
            showOnlineSheet = false
            cancelSubtitleLoad()
        })
    }
    if (showAiKeySheet) {
        SushiAiKeyMissingSheet(
            onDismissRequest = { showAiKeySheet = false },
            initialMessage = aiKeySheetMessage,
        )
    }
    subtitleBusy?.let { SushiSubtitleBusyOverlay(it, onCancel = { cancelSubtitleLoad() }) }

    if (showChapterDialog) {
        ChapterSelectionSheet(
            onSelected = {
                exoPlayer.seekTo(it.time)
                showChapterDialog = false
            },
            onDismiss = {
                showChapterDialog = false
            }
        )
    }

    if (showSpeedDialog) {
        PlaybackSpeedPicker(
            player = exoPlayer,
            onDismissRequest = {
                showSpeedDialog = false
            }
        )
    }
}

// Control Buttons
@Composable
fun PlaybackButtons(
    player: ExoPlayer,
    bottomControlFocusRequester: FocusRequester,
    onPause: () -> Unit,
) {
    val state by VideoPlayerObject.videoPlayerState.collectAsState(null)

    val forwardSpeed by PlayerSettingsObject.forwardSpeed.collectAsState(30.seconds)
    val backwardSpeed by PlayerSettingsObject.backwardSpeed.collectAsState(15.seconds)

    val playbackData by VideoPlayerObject.implementation.playbackData.collectAsState(null)
    val nextVideo = playbackData?.nextVideo
    val previousVideo = playbackData?.previousVideo

    val isPlaying = state?.playing ?: false

    val isTVMode by VideoPlayerObject.implementation.isTVMode.collectAsState(false)

    // These buttons render straight from playbackData and hold no state of their own: every time
    // they have gone dead, the cause was something clearing playbackData underneath them rather
    // than anything in this composable. Note a disabled CustomButton draws at alpha 0.15, which
    // over video reads as "the button isn't there at all" — so a report of missing buttons is not
    // evidence that this block failed to render. Instrument VideoPlayerImplementation.clearSession
    // before touching the UI; see MediaControlsWrapper.onNotificationDeleted for the last case.
    Row(
        modifier = Modifier
            .padding(horizontal = 4.dp, vertical = 6.dp)
            .wrapContentWidth(),
        horizontalArrangement = Arrangement.spacedBy(
            12.dp,
            alignment = Alignment.CenterHorizontally
        ),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (!isTVMode) {
            CustomButton(
                onClick = { VideoPlayerObject.videoPlayerControls?.loadPreviousVideo {} },
                enabled = previousVideo != null,
            ) {
                Icon(
                    Iconsax.Filled.Backward,
                    contentDescription = previousVideo?.title,
                )
            }
            CustomButton(
                onClick = {
                    player.seekTo(
                        player.currentPosition - backwardSpeed.inWholeMilliseconds
                    )
                },
            ) {
                Box(
                    modifier = Modifier
                        .wrapContentSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Iconsax.Outline.Refresh,
                        modifier = Modifier.size(42.dp),
                        contentDescription = "Backwards",
                    )
                    Text(
                        "-${backwardSpeed.inWholeSeconds}",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        }
        CustomButton(
            modifier = Modifier
                .focusRequester(bottomControlFocusRequester)
                .defaultSelected(true),
            enableScaledFocus = true,
            onClick = {
                if (player.isPlaying) {
                    player.pause()
                    onPause()
                } else {
                    player.play()
                }
            },
        ) {
            Icon(
                if (isPlaying) Iconsax.Filled.Pause else Iconsax.Filled.Play,
                modifier = Modifier.size(45.dp),
                contentDescription = if (isPlaying) "Pause" else "Play",
            )
        }
        if (!isTVMode) {
            CustomButton(
                onClick = {
                    player.seekTo(
                        player.currentPosition + forwardSpeed.inWholeMilliseconds
                    )
                },
            ) {
                Box(
                    modifier = Modifier
                        .wrapContentSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Iconsax.Outline.Refresh,
                        contentDescription = "Forward",
                        modifier = Modifier
                            .size(42.dp)
                            .scale(scaleX = -1f, scaleY = 1f),
                    )
                    Text(
                        forwardSpeed.inWholeSeconds.toString(),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }

            CustomButton(
                onClick = { VideoPlayerObject.videoPlayerControls?.loadNextVideo {} },
                enabled = nextVideo != null,
            ) {
                Icon(
                    Iconsax.Filled.Forward,
                    contentDescription = nextVideo?.title,
                )
            }
        }
    }
}

@Composable
internal fun RowScope.LeftButtons(
    openChapterSelection: () -> Unit,
    openPlaybackSpeedPicker: () -> Unit,
) {
    val chapters by VideoPlayerObject.chapters.collectAsState(emptyList())
    val isTVMode by VideoPlayerObject.implementation.isTVMode.collectAsState(false)


    Row(
        modifier = Modifier.weight(1f),
        horizontalArrangement = Arrangement.spacedBy(12.dp, alignment = Alignment.Start)
    ) {
        if (!isTVMode) {
            CustomButton(
                onClick = openChapterSelection,
                enabled = chapters?.isNotEmpty() == true
            ) {
                Icon(
                    Iconsax.Filled.Check,
                    contentDescription = "Show chapters",
                )
            }

            CustomButton(
                onClick = openPlaybackSpeedPicker,
                enabled = true
            ) {
                Icon(
                    Iconsax.Filled.Flash,
                    contentDescription = "Playback Speed",
                )
            }
        }
    }
}

@Composable
internal fun RowScope.RightButtons(
    showAudioDialog: MutableState<Boolean>,
    showSubDialog: MutableState<Boolean>
) {
    val hasAudioTracks by VideoPlayerObject.hasAudioTracks.collectAsState(false)

    val isTVMode by VideoPlayerObject.implementation.isTVMode.collectAsState(false)

    Row(
        modifier = Modifier.weight(1f),
        horizontalArrangement = Arrangement.spacedBy(12.dp, alignment = Alignment.End)
    ) {
        if (isTVMode) {
            CustomButton(
                onClick = {
                    VideoPlayerObject.toggleGuideVisibility()
                },
            ) {
                Icon(
                    Iconsax.Filled.SliderVertical,
                    contentDescription = "TV Guide",
                )
            }
        } else {
            CustomButton(
                enabled = hasAudioTracks,
                onClick = {
                    showAudioDialog.value = true
                },
            ) {
                Icon(
                    Iconsax.Filled.AudioSquare,
                    contentDescription = "Audio Track",
                )
            }
            CustomButton(
                // Always tappable, even with no embedded track — SubtitlePicker still offers
                // Automatic / Online / Translate with AI.
                enabled = true,
                onClick = {
                    showSubDialog.value = true
                },
            ) {
                Icon(
                    Iconsax.Filled.Subtitle,
                    contentDescription = "Subtitles",
                )
            }
        }
    }
}
