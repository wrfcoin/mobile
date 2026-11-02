package com.wrfcoin.wrfcoin_mobile

import android.app.Activity
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.view.Surface
import android.view.WindowManager
import io.flutter.plugin.common.EventChannel

/**
 * Sky View's fused orientation: TYPE_ROTATION_VECTOR, which sensors_plus does
 * not expose. Runs only while the Dart side listens, and the screen cancels on
 * background. Each event is [w, x, y, z, heading accuracy (rad), status, display
 * rotation]. The sensor's azimuth is magnetic; Dart applies declination.
 */
class SkyRotationVectorStream(private val activity: Activity) :
    EventChannel.StreamHandler, SensorEventListener {

    private val sensorManager =
        activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var events: EventChannel.EventSink? = null
    private var status = SensorManager.SENSOR_STATUS_UNRELIABLE
    private val quaternion = FloatArray(4)

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        // Someone holding the phone up at the sky is not touching it.
        activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val sensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (sensor == null) {
            sink.error("unavailable", "This phone has no rotation vector sensor", null)
            return
        }
        events = sink
        sensorManager.registerListener(this, sensor, SAMPLING_PERIOD_US)
    }

    override fun onCancel(arguments: Any?) = stop()

    fun stop() {
        sensorManager.unregisterListener(this)
        events = null
        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onSensorChanged(event: SensorEvent) {
        val sink = events ?: return
        status = event.accuracy
        SensorManager.getQuaternionFromVector(quaternion, event.values)
        val heading = if (event.values.size > 4) event.values[4].toDouble() else -1.0
        sink.success(
            doubleArrayOf(
                quaternion[0].toDouble(),
                quaternion[1].toDouble(),
                quaternion[2].toDouble(),
                quaternion[3].toDouble(),
                heading,
                status.toDouble(),
                displayRotation().toDouble(),
            ),
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        status = accuracy
    }

    @Suppress("DEPRECATION")
    private fun displayRotation(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.rotation ?: Surface.ROTATION_0
        } else {
            activity.windowManager.defaultDisplay.rotation
        }

    private companion object {
        // About 30 Hz: enough for a smooth map, gentler on the battery than
        // SENSOR_DELAY_GAME's 50 Hz.
        const val SAMPLING_PERIOD_US = 33_333
    }
}
