package app.sushi.composables.dialogs

import SubtitleTrack
import androidx.annotation.OptIn
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.unit.dp
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import android.os.Handler
import android.os.Looper
import app.sushi.messengers.properlySetSubAndAudioTracks
import app.sushi.objects.Localized
import app.sushi.objects.Translate
import app.sushi.objects.SushiSubtitleSource
import app.sushi.objects.VideoPlayerObject
import app.sushi.utility.InternalTrack
import app.sushi.utility.clearSubtitleTrack
import app.sushi.utility.isSubtitleTrackDisabled
import app.sushi.utility.setInternalSubtitleTrack

/** Server sent a real subtitle list (more than a lone Off row). */
private fun hasUsableServerSubtitleList(server: List<SubtitleTrack>): Boolean =
    server.isNotEmpty() && (server.size > 1 || server.any { it.index != -1L })

/** Off + one row per muxed Exo text track; indices -1, 1..n match [properlySetSubAndAudioTracks] list layout. */
private fun muxedFallbackSubtitleRows(internal: List<InternalTrack>): List<SubtitleTrack> {
    if (internal.isEmpty()) return emptyList()
    val off = SubtitleTrack(
        name = "Off",
        languageCode = "",
        codec = "",
        index = -1L,
        external = false,
        url = null,
    )
    return listOf(off) + internal.mapIndexed { i, t ->
        SubtitleTrack(
            name = t.label.ifBlank { "Subtitle ${i + 1}" },
            languageCode = t.language.orEmpty(),
            codec = t.codec.orEmpty(),
            index = (i + 1).toLong(),
            external = false,
            url = null,
        )
    }
}

// Sushi Automatic / Online / Translate rows (doc 15 §11). Native picker only listed Off +
// muxed tracks before; these call Flutter over pigeon, then Exo sideload.
@OptIn(UnstableApi::class)
@Composable
fun SubtitlePicker(
    player: ExoPlayer,
    onDismissRequest: () -> Unit,
    onAutomatic: () -> Unit = {},
    onOnline: () -> Unit = {},
    onTranslate: () -> Unit = {},
) {
    val selectedIndex by VideoPlayerObject.currentSubtitleTrackIndex.collectAsState()
    val sushiExternalActive by VideoPlayerObject.sushiExternalSubtitleActive.collectAsState()
    val sushiSource by VideoPlayerObject.sushiSubtitleSource.collectAsState()
    val subTitles by VideoPlayerObject.subtitleTracks.collectAsState(emptyList())
    val internalSubTracks by VideoPlayerObject.exoSubTracks.collectAsState(emptyList())
    // A personal video (ADR 0037) gets only its own muxed tracks: no Automatic, Online or AI.
    val playbackData by VideoPlayerObject.implementation.playbackData.collectAsState()
    val sushiTools = playbackData?.sushiSubtitleTools ?: true

    val effectiveSubTitles = remember(subTitles, internalSubTracks) {
        if (hasUsableServerSubtitleList(subTitles)) {
            subTitles
        } else {
            muxedFallbackSubtitleRows(internalSubTracks).ifEmpty { subTitles }
        }
    }

    LaunchedEffect(subTitles, internalSubTracks) {
        if (internalSubTracks.isEmpty()) return@LaunchedEffect
        if (hasUsableServerSubtitleList(subTitles)) return@LaunchedEffect
        val impl = VideoPlayerObject.implementation
        val cur = impl.playbackData.value ?: return@LaunchedEffect
        val built = muxedFallbackSubtitleRows(internalSubTracks)
        if (built.isEmpty() || cur.subtitleTracks == built) return@LaunchedEffect
        val prevDef = cur.defaultSubtrack
        val userPickedOff = VideoPlayerObject.currentSubtitleTrackIndex.value == -1
        // If Jellyfin default stream index does not exist on rebuilt mux rows (-1,1,2,…), keep
        // "subtitles on" by defaulting to the first real track (index 1), not Off — unless the
        // user explicitly chose Off.
        val newDef = when {
            userPickedOff -> -1L
            built.any { it.index == prevDef } -> prevDef
            prevDef > 0 && built.size > 1 -> 1L
            else -> -1L
        }
        impl.playbackData.value = cur.copy(subtitleTracks = built, defaultSubtrack = newDef)
        VideoPlayerObject.setSubtitleTrackIndex(newDef.toInt(), init = true)
        val patched = impl.playbackData.value
        if (patched != null) {
            Handler(Looper.getMainLooper()).post {
                player.properlySetSubAndAudioTracks(patched)
            }
        }
    }

    val focusRequesters = remember(effectiveSubTitles) {
        effectiveSubTitles.associateWith { FocusRequester() }
    }

    val listState = rememberLazyListState()

    LaunchedEffect(selectedIndex, effectiveSubTitles) {
        val selectedSubIndex = effectiveSubTitles.indexOfFirst { it.index == selectedIndex.toLong() }

        if (selectedSubIndex in effectiveSubTitles.indices) {
            listState.scrollToItem(selectedSubIndex)
            focusRequesters[effectiveSubTitles[selectedSubIndex]]?.requestFocus()
        }
    }

    CustomModalBottomSheet(
        onDismissRequest,
        maxWidth = 600.dp,
    ) {
        LazyColumn(
            state = listState,
            modifier = Modifier
                .wrapContentWidth()
                .padding(horizontal = 8.dp, vertical = 16.dp),
        ) {
            if (sushiTools) {
            item {
                TrackButton(
                    modifier = Modifier.fillMaxWidth(),
                    selected = sushiExternalActive && sushiSource == SushiSubtitleSource.Automatic,
                    onClick = {
                        VideoPlayerObject.armedSushiSubtitleSource = SushiSubtitleSource.Automatic
                        onAutomatic()
                        onDismissRequest()
                    },
                ) { Text("Automatic (online)") }
            }
            item {
                TrackButton(
                    modifier = Modifier.fillMaxWidth(),
                    selected = sushiExternalActive && sushiSource == SushiSubtitleSource.Online,
                    onClick = {
                        VideoPlayerObject.armedSushiSubtitleSource = SushiSubtitleSource.Online
                        onOnline()
                        onDismissRequest()
                    },
                ) { Text("Online subtitles…") }
            }
            item {
                TrackButton(
                    modifier = Modifier.fillMaxWidth(),
                    selected = sushiExternalActive && sushiSource == SushiSubtitleSource.Ai,
                    onClick = {
                        VideoPlayerObject.armedSushiSubtitleSource = SushiSubtitleSource.Ai
                        onTranslate()
                        onDismissRequest()
                    },
                ) { Text("Translate with AI") }
            }
            item {
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            }
            }
            val textDisabled = player.isSubtitleTrackDisabled()
            effectiveSubTitles.forEachIndexed { index, serverSub ->
                val isOffTrack = serverSub.index == -1L
                // Sideloaded Automatic / Online / AI is not one of these rows.
                val selected = !sushiExternalActive && if (isOffTrack) {
                    selectedIndex == -1 || textDisabled
                } else {
                    !textDisabled && serverSub.index == selectedIndex.toLong()
                }

                item {
                    TrackButton(
                        modifier = Modifier
                            .fillMaxWidth()
                            .focusRequester(focusRequesters[serverSub]!!),
                        onClick = {
                            val serverList =
                                VideoPlayerObject.implementation.playbackData.value?.subtitleTracks.orEmpty()
                            val shouldSyncFlutter = serverList.isNotEmpty() &&
                                !(serverList.size == 1 && serverList[0].index == -1L)
                            if (isOffTrack) {
                                VideoPlayerObject.sushiExternalSubtitleActive.value = false
                                VideoPlayerObject.sushiSubtitleSource.value = SushiSubtitleSource.None
                                VideoPlayerObject.armedSushiSubtitleSource = SushiSubtitleSource.None
                                VideoPlayerObject.pendingInternalSubtitle = null
                                VideoPlayerObject.setSubtitleTrackIndex(-1, init = !shouldSyncFlutter)
                                player.clearSubtitleTrack()
                            } else {
                                val internalTrackIndex =
                                    effectiveSubTitles.take(index).count { it.index != -1L }

                                val internalSubTrack =
                                    internalSubTracks.elementAtOrNull(internalTrackIndex)

                                if (internalSubTrack != null) {
                                    VideoPlayerObject.sushiExternalSubtitleActive.value = false
                                    VideoPlayerObject.sushiSubtitleSource.value = SushiSubtitleSource.None
                                    VideoPlayerObject.armedSushiSubtitleSource = SushiSubtitleSource.None
                                    VideoPlayerObject.setSubtitleTrackIndex(
                                        serverSub.index.toInt(),
                                        init = !shouldSyncFlutter,
                                    )
                                    player.setInternalSubtitleTrack(internalSubTrack)
                                }
                            }
                        },
                        selected = selected,
                    ) {
                        if (isOffTrack) {
                            Translate(Localized::off) {
                                Text(it)
                            }
                        } else {
                            Text(
                                text = serverSub.name,
                            )
                        }
                    }
                }
            }
        }
    }
}