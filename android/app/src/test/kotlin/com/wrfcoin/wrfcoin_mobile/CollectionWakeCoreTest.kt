package com.wrfcoin.wrfcoin_mobile

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager

// The rule under test: the lock is only given back while an alarm is set to
// bring the next tick. Run with: ./gradlew :app:testDebugUnitTest
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CollectionWakeCoreTest {
    private val interval = 15 * 60 * 1000L
    private val hold = 11 * 60 * 1000L

    private lateinit var context: Context
    private lateinit var alarms: AlarmManager
    private var running = true
    private val messages = mutableListOf<String>()
    private var onNotify: () -> Unit = {}
    private lateinit var core: CollectionWakeCore

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        running = true
        messages.clear()
        onNotify = {}
        core = CollectionWakeCore(context, { running }, {
            onNotify()
            messages.add(it)
        })
    }

    private fun pending(action: String, code: Int): PendingIntent? =
        PendingIntent.getBroadcast(
            context,
            code,
            Intent(context, CollectionAlarmReceiver::class.java).setAction(action),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun exact() = pending(CollectionWakeCore.ALARM_ACTION, 8881)

    private fun watchdog() = pending(CollectionWakeCore.WATCHDOG_ACTION, 8882)

    private fun scheduled(action: String) =
        shadowOf(alarms).scheduledAlarms.filter {
            shadowOf(it.operation).savedIntent.action == action
        }

    private fun exactAlarm() = scheduled(CollectionWakeCore.ALARM_ACTION).single()

    private fun watchdogAlarm() = scheduled(CollectionWakeCore.WATCHDOG_ACTION).single()

    private fun intervalExtra(action: String) =
        shadowOf(scheduled(action).single().operation).savedIntent
            .getLongExtra(CollectionWakeCore.EXTRA_INTERVAL_MS, -1)

    @Test
    fun `engine start takes the lock before Dart runs`() {
        assertFalse(core.lockHeld)
        core.engineCreated()
        assertTrue(core.lockHeld)
        assertFalse(core.heldBetweenTicks)
    }

    @Test
    fun `a tick sets an exact wake-up alarm and a later watchdog, then lets go`() {
        val now = SystemClock.elapsedRealtime()
        assertTrue(core.beginTick(interval, hold))
        assertTrue(core.lockHeld)
        assertEquals(AlarmManager.ELAPSED_REALTIME_WAKEUP, exactAlarm().type)
        assertEquals(now + interval, exactAlarm().triggerAtMs)
        assertTrue(exactAlarm().isAllowWhileIdle)
        assertEquals(AlarmManager.ELAPSED_REALTIME_WAKEUP, watchdogAlarm().type)
        assertEquals(
            now + interval + CollectionWakeCore.WATCHDOG_GRACE_MS,
            watchdogAlarm().triggerAtMs,
        )
        assertTrue(watchdogAlarm().isAllowWhileIdle)

        assertTrue(core.endTick(0))
        assertFalse(core.lockHeld)
        assertTrue(core.alarmArmed)
    }

    @Test
    fun `without the battery exemption the lock is held and no alarm is set`() {
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        assertFalse(core.beginTick(interval, hold))
        assertTrue(core.heldBetweenTicks)
        assertNull(exact())
        assertNull(watchdog())

        assertFalse(core.endTick(0))
        assertTrue(core.lockHeld)
        assertTrue(core.heldBetweenTicks)
    }

    @Test
    fun `the alarm takes the lock and sets the next one before telling the service`() {
        core.beginTick(interval, hold)
        core.endTick(0)
        var lockHeldWhenTold = false
        var armedWhenTold = false
        onNotify = {
            lockHeldWhenTold = core.lockHeld
            armedWhenTold = core.alarmArmed && exact() != null
        }
        core.onAlarm(interval, hold)
        assertEquals(listOf("collection_alarm:1"), messages)
        assertTrue(lockHeldWhenTold)
        assertTrue(armedWhenTold)
    }

    @Test
    fun `the alarm re-arms with the interval, never a leftover delay`() {
        core.beginTick(interval, hold)
        // The interval setting changed and the next tick is already due.
        assertTrue(core.reschedule(0, interval, hold))
        val now = SystemClock.elapsedRealtime()
        assertEquals(now, exactAlarm().triggerAtMs)
        assertEquals(interval, intervalExtra(CollectionWakeCore.ALARM_ACTION))

        core.onAlarm(intervalExtra(CollectionWakeCore.ALARM_ACTION), hold)
        assertEquals(now + interval, exactAlarm().triggerAtMs)
        assertEquals(
            now + interval + CollectionWakeCore.WATCHDOG_GRACE_MS,
            watchdogAlarm().triggerAtMs,
        )
    }

    @Test
    fun `exemption removed, alarm fires mid-tick - the tick ends still holding the lock`() {
        core.beginTick(interval, hold)
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        core.onAlarm(interval, hold)
        assertFalse(core.alarmArmed)
        assertTrue(core.heldBetweenTicks)
        assertNull(exact())
        assertNull(watchdog())

        // Dart dropped that alarm; the running tick ends.
        assertFalse(core.endTick(1))
        assertTrue(core.lockHeld)
        assertTrue(core.heldBetweenTicks)
    }

    @Test
    fun `exemption removed during a tick - ending it keeps the lock`() {
        core.beginTick(interval, hold)
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        assertFalse(core.endTick(0))
        assertTrue(core.lockHeld)
        assertTrue(core.heldBetweenTicks)
        assertNull(exact())
    }

    @Test
    fun `exemption removed between ticks - the watchdog's tick ends holding the lock`() {
        core.beginTick(interval, hold)
        core.endTick(0)
        assertFalse(core.lockHeld)
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        // Android dropped the exact alarm; the inexact one still fires.
        core.onAlarm(interval, hold)
        assertEquals(1, messages.size)
        assertTrue(core.heldBetweenTicks)
        assertFalse(core.beginTick(interval, hold))
        assertFalse(core.endTick(1))
        assertTrue(core.lockHeld)
    }

    @Test
    fun `exemption given back - the held lock becomes a tick lock again`() {
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        core.beginTick(interval, hold)
        core.endTick(0)
        assertTrue(core.heldBetweenTicks)
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        assertTrue(core.beginTick(interval, hold))
        assertTrue(core.endTick(0))
        assertFalse(core.lockHeld)
        assertNotNull(exact())
    }

    @Test
    fun `an alarm Dart has not heard of keeps the lock for its own tick`() {
        core.beginTick(interval, hold)
        core.onAlarm(interval, hold)
        assertTrue(core.endTick(0))
        assertTrue(core.lockHeld)
        assertFalse(core.heldBetweenTicks)
        assertTrue(core.endTick(1))
        assertFalse(core.lockHeld)
    }

    @Test
    fun `a stopped service gets no lock, no message and no further alarm`() {
        core.beginTick(interval, hold)
        core.endTick(0)
        running = false
        core.onAlarm(interval, hold)
        assertTrue(messages.isEmpty())
        assertFalse(core.lockHeld)
        assertFalse(core.alarmArmed)
        assertNull(exact())
        assertNull(watchdog())
    }

    @Test
    fun `stopping cancels both alarms and gives the lock back`() {
        core.beginTick(interval, hold)
        core.stop()
        assertFalse(core.lockHeld)
        assertFalse(core.alarmArmed)
        assertNull(exact())
        assertNull(watchdog())
        assertTrue(shadowOf(alarms).scheduledAlarms.isEmpty())
    }

    @Test
    fun `the alarm is not moved when the lock is the held kind`() {
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        core.beginTick(interval, hold)
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        assertFalse(core.reschedule(1000, interval, hold))
        assertNull(exact())
        assertTrue(core.heldBetweenTicks)
    }
}
