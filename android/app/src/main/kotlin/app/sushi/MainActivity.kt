package app.sushi

import BatteryOptimizationPigeon
import FlutterError
import LocalNetworkPermissionPigeon
import NativeVideoActivity
import SushiTdlibBridgeApi
import PlayerSettingsPigeon
import StartResult
import TranslationsPigeon
import VideoPlayerApi
import VideoPlayerControlsCallback
import VideoPlayerListenerCallback
import android.annotation.SuppressLint
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.net.Uri
import android.util.Log
import android.provider.Settings
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import app.sushi.objects.PlayerSettingsObject
import app.sushi.objects.TdlibBridgeObject
import app.sushi.objects.TranslationsMessenger
import app.sushi.objects.VideoPlayerObject
import app.sushi.utility.leanBackEnabled
import androidx.core.net.toUri

class MainActivity : AudioServiceFragmentActivity(), NativeVideoActivity {

    private lateinit var videoPlayerLauncher: ActivityResultLauncher<Intent>
    private var videoPlayerCallback: ((Result<StartResult>) -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // TV launcher re-entry while VideoPlayerActivity is still on the task.
        // MainActivity is singleTop, so it is only reused when it is already the top
        // activity. With the player on top, LEANBACK_LAUNCHER creates a second
        // MainActivity (and a second Flutter engine) above the still-living player.
        // Playing again then starts a second VideoPlayerActivity. Both ExoPlayers
        // stay decoded — on this box that is media.swcodec — and both write
        // PlaybackState, so the play/pause button flickers. Finish before
        // super.onCreate so the second engine never attaches.
        val launchIntent = intent
        if (!isTaskRoot &&
            launchIntent.action == Intent.ACTION_MAIN &&
            (launchIntent.hasCategory(Intent.CATEGORY_LAUNCHER) ||
                launchIntent.hasCategory(Intent.CATEGORY_LEANBACK_LAUNCHER))
        ) {
            Log.d("SUSHI_PROGRESS", "duplicate launcher MainActivity finish before engine start")
            finish()
            return
        }
        // Android 15+ enforces edge-to-edge for SDK 35+ targets; enableEdgeToEdge()
        // is the backward-compatible way to opt in across all supported API levels.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val videoPlayerHost = VideoPlayerObject
        NativeVideoActivity.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            this
        )
        VideoPlayerApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            videoPlayerHost.implementation
        )
        videoPlayerHost.videoPlayerListener =
            VideoPlayerListenerCallback(flutterEngine.dartExecutor.binaryMessenger)

        videoPlayerHost.videoPlayerControls =
            VideoPlayerControlsCallback(flutterEngine.dartExecutor.binaryMessenger)

        TranslationsMessenger.translation =
            TranslationsPigeon(flutterEngine.dartExecutor.binaryMessenger)

        PlayerSettingsPigeon.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            api = PlayerSettingsObject
        )

        TdlibBridgeObject.attach(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        SushiTdlibBridgeApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            api = TdlibBridgeObject,
        )

        BatteryOptimizationPigeon.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            api = object : BatteryOptimizationPigeon {
                override fun isIgnoringBatteryOptimizations(): Boolean {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    return pm.isIgnoringBatteryOptimizations(packageName)
                }

                override fun openBatteryOptimizationSettings() {
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                }
            }
        )

        LocalNetworkPermissionPigeon.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            api = object : LocalNetworkPermissionPigeon {
                override fun getAndroidSdkInt(): Long = Build.VERSION.SDK_INT.toLong()
            }
        )

        videoPlayerLauncher = registerForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result ->
            val callback = videoPlayerCallback
            videoPlayerCallback = null

            val startResult = if (result.resultCode == RESULT_OK) {
                StartResult(resultValue = result.data?.getStringExtra("result") ?: "Finished")
            } else {
                StartResult(resultValue = "Cancelled")
            }

                val exo = VideoPlayerObject.implementation.player
                val finalPositionMs = exo?.currentPosition?.coerceAtLeast(0L)
                val finalDurationMs = exo?.duration?.takeIf { it > 0L }
                Log.d(
                    "SUSHI_PROGRESS",
                    "videoPlayerLauncher result resultCode=${result.resultCode} " +
                        "finalPositionMs=$finalPositionMs finalDurationMs=$finalDurationMs",
                )
                exo?.stop()
                exo?.release()
                // Null-out the player before the Dart callback so that any subsequent
                // Dart-side stop() call goes through VideoPlayerImplementation.stop()
                // safely (player?.stop() becomes a null-safe no-op on a released player).
                VideoPlayerObject.implementation.init(null)
                VideoPlayerObject.implementation.clearSession(finalPositionMs, finalDurationMs)
                VideoPlayerObject.tvGuide.value = null
                callback?.invoke(Result.success(startResult))
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Ensure the Activity's intent is updated so Flutter (and plugins / AutoRoute) receive runtime deep-links.
        setIntent(intent)
    }

    override fun launchActivity(callback: (Result<StartResult>) -> Unit) {
        try {
            videoPlayerCallback = callback
            val intent = Intent(this, VideoPlayerActivity::class.java)
            videoPlayerLauncher.launch(intent)
        } catch (e: Exception) {
            e.printStackTrace()
            callback(Result.failure(e))
        }
    }

    override fun disposeActivity() {
        VideoPlayerObject.implementation.stop()
        VideoPlayerObject.tvGuide.value = null
        VideoPlayerObject.currentActivity?.finish()
    }

    override fun isLeanBackEnabled(): Boolean = leanBackEnabled(applicationContext)
}
