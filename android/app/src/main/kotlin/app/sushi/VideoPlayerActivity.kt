package app.sushi

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.graphics.PixelFormat
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.Rational
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.annotation.OptIn
import androidx.annotation.RequiresApi
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.media3.common.util.UnstableApi
import app.sushi.composables.controls.CustomVideoControls
import app.sushi.composables.overlays.screensavers.ScreenSaver
import app.sushi.messengers.sushiBlackLog
import app.sushi.objects.VideoPlayerObject
import app.sushi.player.ExoPlayer
import app.sushi.utility.ScaledContent
import app.sushi.utility.leanBackEnabled

class VideoPlayerActivity : ComponentActivity() {
    private var isInPip = false
    /** True when this instance replaced another VideoPlayerActivity still on the task. */
    private var supersededPrevious = false

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        sushiBlackLog("activity onCreate this=${System.identityHashCode(this)} restored=${savedInstanceState != null}")
        val previous = VideoPlayerObject.currentActivity
        // Claim this instance before finishing the previous one. The outgoing
        // composition then sees it was superseded and releases its ExoPlayer
        // without clearSession(), which would wipe the playback the new
        // activity is about to open.
        VideoPlayerObject.currentActivity = this
        if (previous != null && previous !== this && !previous.isFinishing) {
            supersededPrevious = true
            VideoPlayerObject.implementation.player?.pause()
            sushiBlackLog(
                "activity onCreate finishing previous=${System.identityHashCode(previous)}",
            )
            previous.finish()
        }

        window.setFlags(
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
        )

        window.setFormat(PixelFormat.TRANSLUCENT)

        setContent {
            VideoPlayerTheme {
                VideoPlayerScreen()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        isInPip = false
        sushiBlackLog("activity onResume this=${System.identityHashCode(this)}")
        // First onResume after replacing another player: the previous ExoPlayer
        // is still bound until its composition disposes. Restoring here would
        // unpause that zombie. Later resumes (home and back) should restore.
        if (supersededPrevious) {
            supersededPrevious = false
        } else {
            VideoPlayerObject.implementation.restoreAfterBackground()
        }
    }

    override fun onPause() {
        sushiBlackLog("activity onPause this=${System.identityHashCode(this)} isInPip=$isInPip")
        Log.d("SUSHI_PROGRESS", "VideoPlayerActivity.onPause isInPip=$isInPip isFinishing=$isFinishing")
        // Skip pausing playback when entering/already in PiP so the mini window
        // keeps playing while the user is in another app.
        if (!isInPip) {
            VideoPlayerObject.implementation.saveBackgroundState()
            super.onPause()
            VideoPlayerObject.implementation.pause()
        } else {
            super.onPause()
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            tryEnterPip()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        isInPip = isInPictureInPictureMode
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun tryEnterPip() {
        val exo = VideoPlayerObject.implementation.player ?: return
        // Only auto-enter PiP when there is media loaded and actively playing.
        if (exo.mediaItemCount == 0) return
        if (!exo.isPlaying && !exo.playWhenReady) return

        val vs = exo.videoSize
        val w = if (vs.width > 0) vs.width else 16
        val h = if (vs.height > 0) vs.height else 9
        // Android requires PiP aspect ratio in [0.418410, 2.39] (1/2.39 .. 2.39).
        val ratio = w.toFloat() / h.toFloat()
        val clamped = when {
            ratio > 2.39f -> Rational(239, 100)
            ratio < 1f / 2.39f -> Rational(100, 239)
            else -> Rational(w, h)
        }
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(clamped)
            .build()
        try {
            enterPictureInPictureMode(params)
        } catch (_: IllegalStateException) {
            // Activity not in foreground / PiP not allowed at this moment; ignore.
        }
    }

    override fun onDestroy() {
        sushiBlackLog("activity onDestroy this=${System.identityHashCode(this)} isFinishing=$isFinishing")
        Log.d("SUSHI_PROGRESS", "VideoPlayerActivity.onDestroy isFinishing=$isFinishing")
        super.onDestroy()
        if (VideoPlayerObject.currentActivity === this) {
            VideoPlayerObject.currentActivity = null
        }
    }
}

@OptIn(UnstableApi::class)
@Composable
fun VideoPlayerScreen(
) {
    val leanBackEnabled = leanBackEnabled(LocalContext.current)
    ScreenSaver {
        ExoPlayer { player ->
            ScaledContent(
                scale = if (leanBackEnabled) 0.75f else 1f,
                fontScale = if (leanBackEnabled) 1.2f else 1f,
            ) {
                CustomVideoControls(player)
            }
        }
    }
}
