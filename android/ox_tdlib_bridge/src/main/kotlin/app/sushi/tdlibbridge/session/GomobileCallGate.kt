package app.sushi.tdlibbridge.session

import android.util.Log
import go.Seq
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Process-wide serialization for every call that crosses into the gomobile-bound oxtelegram.aar
 * runtime — mobile.Client AND mobile.PlaybackSession alike, since both compile into the same
 * generated JNI layer. Confirmed live, twice, that two such calls entering at once crashes the
 * whole process with `fatal error: bulkBarrierPreWrite: unaligned arguments`, on both an x86_64
 * emulator and an arm64 device: first two Sushi protocol calls overlapping (mobile.Client, fixed
 * with a Dart-side queue too), then stopPlaybackSession's cleanup path (mobile.PlaybackSession.close,
 * via OxTelegramFileFetcher) racing a protocol call.
 *
 * A Kotlin Mutex alone is not enough: [kotlinx.coroutines.Dispatchers.IO] is a pool, so two
 * serialized-in-time callers still hop onto different OS threads, and gomobile's Seq/JNI layer
 * has been observed to fault that way after ExoPlayer.release (DataSource ensureAvailable on a
 * loader thread) overlapping sendTextAndWaitReply. Every JNI entry therefore also runs on one
 * dedicated thread.
 *
 * Shared across [OxTelegramClient], [app.sushi.tdlibbridge.media.OxTelegramFileFetcher], and
 * [app.sushi.tdlibbridge.player.OxTelegramStreamBridge].
 *
 * "Cheap" in-memory gomobile getters (armDeliveryWaiter, deliveryRef, isBotMode) used to skip
 * this gate so a 30s sendTextAndWaitReply would not stall a sync Pigeon poll. Confirmed live
 * 2026-09-19 on Pixel 10 Pro: those JNI entries overlapping HTTP ensureAvailable crashed with
 * the same `bulkBarrierPreWrite: unaligned arguments` during subtitle push + prefetch. Every
 * gomobile entry has to come through here; sync Pigeon uses [tryEnterBlocking] / [enqueue]
 * instead of waiting out a long protocol call on the platform thread.
 *
 * Upstream gomobile still frees Go refs on a separate `GoRefQueue Finalizer Thread` via
 * `Seq.destroyRef`. That JNI entry is invisible to this gate and raced `sendText` during
 * rapid navigation (device log 2026-09-24: `jni run op=sendText running=1` then
 * `bulkBarrierPreWrite`). [installGoRefReleaser] wires Seq.setReleaser so those frees queue
 * onto this same `ox-gomobile` executor — fire-and-forget, never blocking the finalizer
 * thread waiting for a long sendText. Requires the patched Seq.java baked into oxtelegram.aar
 * by `go/oxtelegram/bind-android.ps1`.
 */
object GomobileCallGate {
    val mutex = Mutex()

    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "ox-gomobile").apply { isDaemon = true }
    }
    val dispatcher = executor.asCoroutineDispatcher()

    private val enqueueScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val running = AtomicInteger(0)
    private val releaserInstalled = AtomicBoolean(false)

    /**
     * Install before the first [mobile.Client] / [mobile.PlaybackSession] proxy is created so
     * every GoRefQueue destroy routes through [executor]. Idempotent.
     */
    fun installGoRefReleaser() {
        if (!releaserInstalled.compareAndSet(false, true)) return
        Seq.touch()
        Seq.setReleaser { refnum ->
            Log.i("OXPLAY_TDLIB", "jni enqueue op=destroyRef refnum=$refnum")
            executor.execute {
                val n = running.incrementAndGet()
                Log.i("OXPLAY_TDLIB", "jni run op=destroyRef running=$n")
                try {
                    Seq.releaseOnCallerThread(refnum)
                } finally {
                    Log.i("OXPLAY_TDLIB", "jni done op=destroyRef running=${running.decrementAndGet()}")
                }
            }
        }
        Log.i("OXPLAY_TDLIB", "gomobile GoRef releaser installed on ox-gomobile")
    }

    suspend fun <T> enter(op: String = "jni", block: () -> T): T {
        Log.i("OXPLAY_TDLIB", "jni wait op=$op")
        return mutex.withLock {
            val n = running.incrementAndGet()
            Log.i("OXPLAY_TDLIB", "jni run op=$op running=$n")
            try {
                withContext(dispatcher) { block() }
            } finally {
                Log.i("OXPLAY_TDLIB", "jni done op=$op running=${running.decrementAndGet()}")
            }
        }
    }

    /**
     * Sync Pigeon / platform-thread reads. If a long JNI holder already owns the gate, return
     * [ifBusy] (a Kotlin cache) instead of blocking the UI thread for the holder's full timeout.
     *
     * Lock order matches [enter]: acquire [mutex] first, then hop onto [dispatcher]. Never launch
     * onto [dispatcher] and then wait for [mutex] — that deadlocks the single ox-gomobile thread
     * against a holder already queued for it.
     */
    fun <T> tryEnterBlocking(op: String = "jni", ifBusy: () -> T, block: () -> T): T {
        if (!mutex.tryLock()) {
            Log.i("OXPLAY_TDLIB", "jni busy op=$op")
            return ifBusy()
        }
        val n = running.incrementAndGet()
        Log.i("OXPLAY_TDLIB", "jni run op=$op running=$n")
        return try {
            runBlocking(dispatcher) { block() }
        } finally {
            Log.i("OXPLAY_TDLIB", "jni done op=$op running=${running.decrementAndGet()}")
            mutex.unlock()
        }
    }

    /** Fire-and-forget JNI (armDeliveryWaiter). Same lock order as [enter]. */
    fun enqueue(op: String = "jni", block: () -> Unit) {
        Log.i("OXPLAY_TDLIB", "jni enqueue op=$op")
        enqueueScope.launch {
            mutex.withLock {
                val n = running.incrementAndGet()
                Log.i("OXPLAY_TDLIB", "jni run op=$op running=$n")
                try {
                    withContext(dispatcher) { block() }
                } finally {
                    Log.i("OXPLAY_TDLIB", "jni done op=$op running=${running.decrementAndGet()}")
                }
            }
        }
    }
}
