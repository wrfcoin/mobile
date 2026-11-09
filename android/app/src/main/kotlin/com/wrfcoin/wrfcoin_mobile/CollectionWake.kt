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
// only, with a time limit, and Dart gives it back when the tick is done.
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

object CollectionWake : FlutterForegroundTaskLifecycleListener {
    const val CHANNEL = "com.wrfcoin.wrfcoin_mobile/collection_wake"
    const val ALARM_ACTION = "com.wrfcoin.wrfcoin_mobile.COLLECTION_ALARM"
    const val ALARM_MESSAGE = "collection_alarm"
    const val EXTRA_DELAY_MS = "delayMs"
    const val EXTRA_HOLD_MS = "holdMs"
    private const val ALARM_REQUEST_CODE = 8881
    private const val WAKE_LOCK_TAG = "wrfcoin:collection_tick"

    private var appContext: Context? = null
    private var channel: MethodChannel? = null
    private var wakeLock: PowerManager.WakeLock? = null

    fun install(context: Context) {
        appContext = context.applicationContext
        FlutterForegroundTaskPlugin.addTaskLifecycleListener(this)
    }

    override fun onEngineCreate(flutterEngine: FlutterEngine?) {
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger ?: return
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(::onMethodCall)
        }
    }

    override fun onTaskStart(starter: FlutterForegroundTaskStarter) {}

    override fun onTaskRepeatEvent() {}

    override fun onTaskDestroy() {}

    // The service is going away, however it was stopped: leave nothing behind.
    override fun onEngineWillDestroy() {
        channel?.setMethodCallHandler(null)
        channel = null
        cancelAlarm()
        release()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquire" -> {
                acquire(call.argument<Number>("timeoutMs")?.toLong())
                result.success(null)
            }
            "release" -> {
                release()
                result.success(null)
            }
            "scheduleAlarm" -> {
                val delayMs = call.argument<Number>("delayMs")?.toLong()
                val holdMs = call.argument<Number>("holdMs")?.toLong()
                if (delayMs == null || holdMs == null || delayMs < 0 || holdMs <= 0) {
                    result.error("bad_args", "delayMs and holdMs are required", null)
                    return
                }
                result.success(scheduleAlarm(delayMs, holdMs))
            }
            "cancelAlarm" -> {
                cancelAlarm()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // One lock, not counted: taking it again only restarts its time limit.
    // With no time limit it is held until release, as the service used to do;
    // that is the fallback when no alarm can be set.
    @SuppressLint("WakelockTimeout")
    @Synchronized
    fun acquire(timeoutMs: Long?) {
        val context = appContext ?: return
        val lock = wakeLock ?: (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
            .apply { setReferenceCounted(false) }
            .also { wakeLock = it }
        if (timeoutMs != null && timeoutMs > 0) lock.acquire(timeoutMs) else lock.acquire()
    }

    @Synchronized
    fun release() {
        wakeLock?.let { if (it.isHeld) it.release() }
    }

    private fun alarmIntent(context: Context, delayMs: Long, holdMs: Long): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST_CODE,
            Intent(context, CollectionAlarmReceiver::class.java)
                .setAction(ALARM_ACTION)
                .putExtra(EXTRA_DELAY_MS, delayMs)
                .putExtra(EXTRA_HOLD_MS, holdMs),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    // An exact alarm that also fires in doze. Android 12 and later allow one
    // without a new permission only for an app let off battery limits; anyone
    // else gets false and the caller keeps the lock held instead.
    fun scheduleAlarm(delayMs: Long, holdMs: Long): Boolean {
        val context = appContext ?: return false
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarms.canScheduleExactAlarms()) {
            cancelAlarm()
            return false
        }
        return try {
            alarms.setExactAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + delayMs,
                alarmIntent(context, delayMs, holdMs),
            )
            true
        } catch (e: SecurityException) {
            cancelAlarm()
            false
        }
    }

    fun cancelAlarm() {
        val context = appContext ?: return
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        alarms.cancel(alarmIntent(context, 0, 1))
    }

    // Runs on the main thread, while the alarm's own lock is still held.
    fun onAlarm(delayMs: Long, holdMs: Long) {
        // A service that is gone gets no tick, no lock and no further alarm.
        if (!ForegroundService.isRunningServiceState.value) return
        acquire(holdMs)
        // Set the next one here too, so the chain survives a tick that Dart
        // drops or never finishes. A tick that runs sets it again.
        if (delayMs > 0) scheduleAlarm(delayMs, holdMs)
        ForegroundService.sendData(ALARM_MESSAGE)
    }
}

class CollectionAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != CollectionWake.ALARM_ACTION) return
        val holdMs = intent.getLongExtra(CollectionWake.EXTRA_HOLD_MS, 0)
        if (holdMs <= 0) return
        CollectionWake.onAlarm(intent.getLongExtra(CollectionWake.EXTRA_DELAY_MS, 0), holdMs)
    }
}
