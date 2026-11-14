package com.wrfcoin.wrfcoin_mobile

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.Application
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import com.pravera.flutter_foreground_task.service.ForegroundService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// Keeps the Collect service's CPU use to the ticks themselves. The service
// used to hold a wake lock for as long as it ran, so the phone never slept.
// Now an alarm wakes the phone for each tick, the lock is taken for that tick
// only, with a time limit, and given back when the tick is done.
//
// The service runs in its own Flutter engine, which never sees MainActivity,
// so the channel is attached from the application through the plugin's
// lifecycle listener.
class WrfcoinApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        CollectionWake.install(this)
    }
}

/**
 * The lock and the alarms. One rule holds everything together: the lock is
 * only ever given back while an alarm is set to bring the next tick. Whenever
 * that cannot be said, the lock is held with no time limit, as the service
 * always used to hold it, so a reading never depends on an alarm that is not
 * there.
 */
class CollectionWakeCore(
    context: Context,
    private val serviceRunning: () -> Boolean,
    private val notifyService: (String) -> Unit,
) {
    companion object {
        const val ALARM_ACTION = "com.wrfcoin.wrfcoin_mobile.COLLECTION_ALARM"
        const val WATCHDOG_ACTION = "com.wrfcoin.wrfcoin_mobile.COLLECTION_WATCHDOG"
        const val ALARM_MESSAGE = "collection_alarm"
        const val EXTRA_INTERVAL_MS = "intervalMs"
        const val EXTRA_HOLD_MS = "holdMs"
        const val WAKE_LOCK_TAG = "wrfcoin:collection_tick"

        /** The lock's limit until Dart has said what it wants. */
        const val DEFAULT_HOLD_MS = 11 * 60 * 1000L

        /** How long after the exact alarm the inexact one is due. */
        const val WATCHDOG_GRACE_MS = 2 * 60 * 1000L
        private const val ALARM_REQUEST_CODE = 8881
        private const val WATCHDOG_REQUEST_CODE = 8882
    }

    private val context: Context = context.applicationContext
    private val alarms: AlarmManager? =
        this.context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
    private val wakeLock: PowerManager.WakeLock =
        (this.context.getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
            // Not counted: taking it again only restarts or removes its limit.
            .apply { setReferenceCounted(false) }

    /** Whether an exact alarm is set for the next tick. */
    var alarmArmed = false
        private set

    /** Whether the lock is held with no time limit. */
    var heldBetweenTicks = false
        private set

    /** Counts alarms delivered, so a tick that ends can tell one is on its way. */
    var alarmSeq = 0L
        private set

    val lockHeld: Boolean get() = wakeLock.isHeld

    /**
     * The service's engine is starting. Nothing has set an alarm yet and Dart
     * has not run, so without this the CPU could sleep before the first tick
     * and nothing would wake it.
     */
    @Synchronized
    fun engineCreated() {
        if (!heldBetweenTicks) acquireTimed(DEFAULT_HOLD_MS)
    }

    /** A tick starts: lock for the tick, alarm for the next. Returns [alarmArmed]. */
    @Synchronized
    fun beginTick(intervalMs: Long, holdMs: Long): Boolean {
        acquireTimed(holdMs)
        return armOrHold(intervalMs, intervalMs, holdMs)
    }

    /**
     * A tick ended. Gives the lock back only if an alarm is still set and
     * still allowed. [seenAlarmSeq] is the last alarm Dart has heard of: if a
     * later one was delivered, its tick is about to start and owns the lock.
     * Returns [alarmArmed].
     */
    @Synchronized
    fun endTick(seenAlarmSeq: Long): Boolean {
        if (!alarmArmed || !canScheduleExact()) {
            cancelAlarms()
            hold()
            return false
        }
        if (alarmSeq <= seenAlarmSeq) release()
        return true
    }

    /** Moves the next alarm, if alarms drive the ticks. Returns [alarmArmed]. */
    @Synchronized
    fun reschedule(delayMs: Long, intervalMs: Long, holdMs: Long): Boolean {
        if (!alarmArmed) return false
        return armOrHold(delayMs, intervalMs, holdMs)
    }

    /** The service is going away, however it was stopped: leave nothing behind. */
    @Synchronized
    fun stop() {
        cancelAlarms()
        release()
    }

    /**
     * An alarm fired. Runs on the main thread while the alarm's own lock is
     * held. The lock is taken before anything else, the next alarm is set
     * here (with the interval, never a leftover delay) so the chain does not
     * depend on Dart, and only then is the service told.
     */
    @Synchronized
    fun onAlarm(intervalMs: Long, holdMs: Long) {
        if (!serviceRunning()) {
            // A service that is gone gets no tick, no lock and no further alarm.
            cancelAlarms()
            return
        }
        acquireTimed(holdMs)
        alarmSeq++
        armOrHold(intervalMs, intervalMs, holdMs)
        notifyService("$ALARM_MESSAGE:$alarmSeq")
    }

    private fun canScheduleExact(): Boolean {
        val manager = alarms ?: return false
        // Android 12 and later allow an exact alarm without a new permission
        // only for an app let off battery limits.
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
    }

    // Sets the exact alarm and, a little after it, an inexact one that needs
    // no permission and is not dropped when the exact one is. If the exact
    // alarm cannot be set, the lock is held instead.
    private fun armOrHold(delayMs: Long, intervalMs: Long, holdMs: Long): Boolean {
        val manager = alarms
        var armed = false
        if (manager != null && canScheduleExact()) {
            val at = SystemClock.elapsedRealtime() + delayMs
            try {
                manager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    at,
                    pendingIntent(ALARM_REQUEST_CODE, ALARM_ACTION, intervalMs, holdMs),
                )
                manager.setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    at + WATCHDOG_GRACE_MS,
                    pendingIntent(WATCHDOG_REQUEST_CODE, WATCHDOG_ACTION, intervalMs, holdMs),
                )
                armed = true
            } catch (e: SecurityException) {
                armed = false
            }
        }
        if (armed) {
            alarmArmed = true
        } else {
            cancelAlarms()
            hold()
        }
        return armed
    }

    private fun intent(action: String) =
        Intent(context, CollectionAlarmReceiver::class.java).setAction(action)

    private fun pendingIntent(code: Int, action: String, intervalMs: Long, holdMs: Long) =
        PendingIntent.getBroadcast(
            context,
            code,
            intent(action).putExtra(EXTRA_INTERVAL_MS, intervalMs).putExtra(EXTRA_HOLD_MS, holdMs),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun cancelAlarms() {
        alarmArmed = false
        cancel(ALARM_REQUEST_CODE, ALARM_ACTION)
        cancel(WATCHDOG_REQUEST_CODE, WATCHDOG_ACTION)
    }

    // Looks the alarm up without creating or rewriting it.
    private fun cancel(code: Int, action: String) {
        val existing = PendingIntent.getBroadcast(
            context,
            code,
            intent(action),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        alarms?.cancel(existing)
        existing.cancel()
    }

    private fun acquireTimed(timeoutMs: Long) {
        wakeLock.acquire(timeoutMs)
        heldBetweenTicks = false
    }

    @SuppressLint("WakelockTimeout")
    private fun hold() {
        wakeLock.acquire()
        heldBetweenTicks = true
    }

    private fun release() {
        if (wakeLock.isHeld) wakeLock.release()
        heldBetweenTicks = false
    }
}

object CollectionWake : FlutterForegroundTaskLifecycleListener {
    const val CHANNEL = "com.wrfcoin.wrfcoin_mobile/collection_wake"

    private var core: CollectionWakeCore? = null
    private var channel: MethodChannel? = null

    fun install(context: Context) {
        core = CollectionWakeCore(
            context,
            serviceRunning = { ForegroundService.isRunningServiceState.value },
            notifyService = { ForegroundService.sendData(it) },
        )
        FlutterForegroundTaskPlugin.addTaskLifecycleListener(this)
    }

    fun onAlarm(intervalMs: Long, holdMs: Long) {
        core?.onAlarm(intervalMs, holdMs)
    }

    override fun onEngineCreate(flutterEngine: FlutterEngine?) {
        core?.engineCreated()
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger ?: return
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(::onMethodCall)
        }
    }

    override fun onTaskStart(starter: FlutterForegroundTaskStarter) {}

    override fun onTaskRepeatEvent() {}

    override fun onTaskDestroy() {}

    override fun onEngineWillDestroy() {
        channel?.setMethodCallHandler(null)
        channel = null
        core?.stop()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val core = core
        if (core == null) {
            result.error("not_installed", "CollectionWake.install was not called", null)
            return
        }
        fun long(name: String) = call.argument<Number>(name)?.toLong()
        when (call.method) {
            "beginTick" -> {
                val intervalMs = long("intervalMs")
                val holdMs = long("holdMs")
                if (intervalMs == null || holdMs == null || intervalMs <= 0 || holdMs <= 0) {
                    result.error("bad_args", "intervalMs and holdMs are required", null)
                    return
                }
                val armed = core.beginTick(intervalMs, holdMs)
                result.success(
                    mapOf(
                        "armed" to armed,
                        "elapsedRealtimeMs" to SystemClock.elapsedRealtime(),
                        "alarmSeq" to core.alarmSeq,
                    ),
                )
            }
            "endTick" -> result.success(core.endTick(long("seenAlarmSeq") ?: 0))
            "reschedule" -> {
                val delayMs = long("delayMs")
                val intervalMs = long("intervalMs")
                val holdMs = long("holdMs")
                if (delayMs == null || intervalMs == null || holdMs == null ||
                    delayMs < 0 || intervalMs <= 0 || holdMs <= 0
                ) {
                    result.error("bad_args", "delayMs, intervalMs and holdMs are required", null)
                    return
                }
                result.success(core.reschedule(delayMs, intervalMs, holdMs))
            }
            "elapsedRealtime" -> result.success(SystemClock.elapsedRealtime())
            "stop" -> {
                core.stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}

class CollectionAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != CollectionWakeCore.ALARM_ACTION &&
            intent.action != CollectionWakeCore.WATCHDOG_ACTION
        ) {
            return
        }
        val intervalMs = intent.getLongExtra(CollectionWakeCore.EXTRA_INTERVAL_MS, 0)
        val holdMs = intent.getLongExtra(CollectionWakeCore.EXTRA_HOLD_MS, 0)
        if (intervalMs <= 0 || holdMs <= 0) return
        CollectionWake.onAlarm(intervalMs, holdMs)
    }
}
