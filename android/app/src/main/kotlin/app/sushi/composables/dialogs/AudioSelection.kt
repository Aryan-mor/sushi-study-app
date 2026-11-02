package app.sushi.composables.dialogs

import AudioTrack
import androidx.annotation.OptIn
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
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
import android.os.Handler
import android.os.Looper
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import app.sushi.messengers.properlySetSubAndAudioTracks
import app.sushi.objects.Localized
import app.sushi.objects.Translate
import app.sushi.objects.VideoPlayerObject
import app.sushi.utility.InternalTrack
import app.sushi.utility.clearAudioTrack
import app.sushi.utility.setInternalAudioTrack

/** Server sent a per-track audio list that actually covers every muxed Exo track (Off + one row each). */
private fun hasUsableServerAudioList(server: List<AudioTrack>, internalCount: Int): Boolean =
    server.size - 1 >= internalCount

/** Off + one row per muxed Exo audio track, labeled from the track's own container language/label.
 *  Used when the server's per-file audio metadata under-reports the real tracks (e.g. Sushi's
 *  `audio_langs` listing fewer languages than are actually muxed in), which otherwise leaves the
 *  extra track(s) with no label and no way to ever show as "selected". Position mirrors
 *  [internal] the way [properlySetSubAndAudioTracks] expects: index 0 is Off, index i+1 is
 *  internal[i]. */
private fun muxedFallbackAudioRows(internal: List<InternalTrack>): List<AudioTrack> {
    if (internal.isEmpty()) return emptyList()
    val off = AudioTrack(
        name = "Off",
        languageCode = "",
        codec = "",
        index = -1L,
        external = false,
    )
    return listOf(off) + internal.mapIndexed { i, t ->
        AudioTrack(
            name = t.language?.trim()?.uppercase()?.ifBlank { null } ?: t.label.ifBlank { "Track ${i + 1}" },
            languageCode = t.language.orEmpty(),
            codec = t.codec.orEmpty(),
            index = i.toLong(),
            external = false,
        )
    }
}

@OptIn(UnstableApi::class)
@Composable
fun AudioPicker(
    player: ExoPlayer,
    onDismissRequest: () -> Unit,
) {
    val selectedIndex by VideoPlayerObject.currentAudioTrackIndex.collectAsState()
    val audioTracks by VideoPlayerObject.audioTracks.collectAsState(emptyList())
    val internalAudioTracks by VideoPlayerObject.exoAudioTracks.collectAsState(emptyList())

    if (internalAudioTracks.isEmpty()) return

    val effectiveAudioTracks = remember(audioTracks, internalAudioTracks) {
        if (hasUsableServerAudioList(audioTracks, internalAudioTracks.size)) {
            audioTracks.drop(1)
        } else {
            muxedFallbackAudioRows(internalAudioTracks).drop(1)
        }
    }

    // Keep the shared playback data (and properlySetSubAndAudioTracks's own idea of the track
    // list) patched to match reality, the same way SubtitlePicker reconciles its list — otherwise
    // a later re-apply (e.g. after sideloading an AI/online subtitle) looks up the old, too-short
    // server list and silently snaps audio back to the default track.
    LaunchedEffect(audioTracks, internalAudioTracks) {
        if (internalAudioTracks.isEmpty()) return@LaunchedEffect
        if (hasUsableServerAudioList(audioTracks, internalAudioTracks.size)) return@LaunchedEffect
        val impl = VideoPlayerObject.implementation
        val cur = impl.playbackData.value ?: return@LaunchedEffect
        val built = muxedFallbackAudioRows(internalAudioTracks)
        if (built.isEmpty() || cur.audioTracks == built) return@LaunchedEffect
        val prevDef = cur.defaultAudioTrack
        val userPickedOff = VideoPlayerObject.currentAudioTrackIndex.value == -1
        val newDef = when {
            userPickedOff -> -1L
            built.any { it.index == prevDef } -> prevDef
            else -> 0L
        }
        impl.playbackData.value = cur.copy(audioTracks = built, defaultAudioTrack = newDef)
        VideoPlayerObject.setAudioTrackIndex(newDef.toInt(), init = true)
        val patched = impl.playbackData.value
        if (patched != null) {
            Handler(Looper.getMainLooper()).post {
                player.properlySetSubAndAudioTracks(patched)
            }
        }
    }

    val focusOffTrack = remember { FocusRequester() }
    val focusRequesters = remember(internalAudioTracks) {
        internalAudioTracks.associateWith { FocusRequester() }
    }

    val listState = rememberLazyListState()

    LaunchedEffect(selectedIndex, effectiveAudioTracks, internalAudioTracks) {
        if (selectedIndex == -1) {
            focusOffTrack.requestFocus()
            return@LaunchedEffect
        }

        val internalIndex = internalAudioTracks.indices.firstOrNull { idx ->
            val trackIndex = effectiveAudioTracks.elementAtOrNull(idx)?.index?.toInt() ?: idx
            trackIndex == selectedIndex
        } ?: -1

        if (internalIndex < 0) {
            focusOffTrack.requestFocus()
            return@LaunchedEffect
        }

        val lazyColumnIndex = internalIndex + 1

        listState.scrollToItem(lazyColumnIndex)
        focusRequesters[internalAudioTracks[internalIndex]]?.requestFocus()
    }

    CustomModalBottomSheet(
        onDismissRequest,
        maxWidth = 600.dp,
    ) {
        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 16.dp),
        ) {
            item {
                val selectedOff = selectedIndex == -1
                TrackButton(
                    modifier = Modifier
                        .fillMaxWidth()
                        .focusRequester(focusOffTrack),
                    onClick = {
                        VideoPlayerObject.setAudioTrackIndex(-1)
                        player.clearAudioTrack()
                    },
                    selected = selectedOff
                ) {
                    Translate(Localized::off) {
                        Text(it)
                    }
                }
            }

            internalAudioTracks.forEachIndexed { index, track ->
                val serverTrack = effectiveAudioTracks.elementAtOrNull(index)
                // Always keep currentAudioTrackIndex in sync with the row actually clicked, even
                // when there's no matching server entry — otherwise it goes stale and a later
                // track re-apply (see the LaunchedEffect above) reverts playback to the old
                // default track.
                val trackIndex = serverTrack?.index?.toInt() ?: index
                // Compare against the reactive (StateFlow-backed) selectedIndex, not a plain
                // player query — reading player.isInternalAudioTrackSelected() here has nothing
                // for Compose to observe, so the tick would only refresh on the next unrelated
                // recomposition (e.g. reopening the sheet) instead of right after the click.
                val selected = selectedIndex == trackIndex

                item {
                    TrackButton(
                        modifier = Modifier
                            .fillMaxWidth()
                            .focusRequester(focusRequesters[track]!!),
                        onClick = {
                            VideoPlayerObject.setAudioTrackIndex(trackIndex)
                            player.setInternalAudioTrack(track)
                        },
                        selected = selected
                    ) {
                        Text(serverTrack?.name ?: track.label.ifBlank { "Track ${index + 1}" })
                    }
                }
            }
        }
    }
}
