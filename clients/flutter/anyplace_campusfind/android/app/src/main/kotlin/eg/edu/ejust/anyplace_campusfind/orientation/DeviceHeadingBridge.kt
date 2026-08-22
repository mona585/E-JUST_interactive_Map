package eg.edu.ejust.anyplace_campusfind.orientation

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import android.view.WindowManager
import io.flutter.plugin.common.EventChannel
import kotlin.math.abs

/**
 * Streams the device's horizontal heading (azimuth, 0..360 degrees clockwise
 * from true-north-referenced magnetic north) to Dart.
 *
 * Sensor: TYPE_ROTATION_VECTOR (fused accelerometer + magnetometer + gyroscope
 * where available) — preferred over raw magnetometer readings.
 *
 * Screen-orientation aware: the rotation matrix is remapped for the current
 * display rotation so holding the phone normally yields the expected heading
 * regardless of natural device orientation.
 *
 * Delivery policy (tuned for an instantly-responsive direction indicator):
 *  - SENSOR_DELAY_GAME (~50 Hz source rate)
 *  - events forwarded immediately when the heading changed by >= MIN_DELTA_DEG
 *  - otherwise a periodic refresh at least every PERIODIC_REFRESH_MS keeps the
 *    stream alive without flooding Dart
 *  - hard floor MIN_INTERVAL_MS between emissions (~30/s upper bound)
 *
 * EventChannel payload: Double heading degrees [0, 360).
 */
class DeviceHeadingBridge(
    context: Context,
    private val sensorManager: SensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
) : EventChannel.StreamHandler, SensorEventListener {

    companion object {
        const val CHANNEL_NAME = "eg.edu.ejust.anyplace_campusfind/heading_stream"

        private const val TAG = "DeviceHeading"

        /** Upper bound on emissions (~30 per second). */
        private const val MIN_INTERVAL_MS = 33L

        /** Minimum heading change to forward an event immediately. */
        private const val MIN_DELTA_DEG = 1.2f

        /** Even without change, refresh periodically so Dart knows the stream is alive. */
        private const val PERIODIC_REFRESH_MS = 300L

        /** Shortest signed angular difference a->b in degrees (-180..180). */
        private fun angleDelta(a: Float, b: Float): Float {
            var d = (b - a) % 360f
            if (d > 180f) d -= 360f
            if (d < -180f) d += 360f
            return d
        }
    }

    private val appContext = context.applicationContext
    private val rotationVectorSensor: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var sink: EventChannel.EventSink? = null
    private var listening = false

    private var lastEmitElapsedMs = 0L
    private var lastEmittedHeading = Float.NaN

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        if (listening) return

        val sensor = rotationVectorSensor
        if (sensor == null) {
            Log.w(TAG, "TYPE_ROTATION_VECTOR not available on this device")
            events?.error("SENSOR_UNAVAILABLE", "Rotation vector sensor not available", null)
            return
        }

        listening = true
        lastEmittedHeading = Float.NaN
        lastEmitElapsedMs = 0L
        sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
        Log.d(TAG, "Heading stream started (rotation vector, GAME rate)")
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        listening = false
        sink = null
        Log.d(TAG, "Heading stream stopped")
    }

    override fun onSensorChanged(event: SensorEvent?) {
        val events = sink ?: return
        if (event == null || event.sensor.type != Sensor.TYPE_ROTATION_VECTOR) return

        val rotationMatrix = FloatArray(9)
        // Void in the Android SDK; throws IllegalArgumentException on bad input.
        try {
            SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
        } catch (e: IllegalArgumentException) {
            return
        }

        // Remap according to current display rotation.
        val display = try {
            @Suppress("DEPRECATION")
            (appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
                .defaultDisplay
        } catch (e: Exception) {
            null
        }
        val adjusted = FloatArray(9)
        when (display?.rotation ?: Surface.ROTATION_0) {
            Surface.ROTATION_90 ->
                SensorManager.remapCoordinateSystem(
                    rotationMatrix, SensorManager.AXIS_Y, SensorManager.AXIS_MINUS_X, adjusted
                )
            Surface.ROTATION_270 ->
                SensorManager.remapCoordinateSystem(
                    rotationMatrix, SensorManager.AXIS_MINUS_Y, SensorManager.AXIS_X, adjusted
                )
            Surface.ROTATION_180 ->
                SensorManager.remapCoordinateSystem(
                    rotationMatrix, SensorManager.AXIS_MINUS_X, SensorManager.AXIS_MINUS_Y, adjusted
                )
            else -> System.arraycopy(rotationMatrix, 0, adjusted, 0, 9)
        }

        val orientation = FloatArray(3)
        SensorManager.getOrientation(adjusted, orientation)
        val headingDeg = ((Math.toDegrees(orientation[0].toDouble()) % 360.0) + 360.0) % 360.0

        val now = SystemClock.elapsedRealtime()
        val sinceLast = now - lastEmitElapsedMs

        val delta = if (lastEmittedHeading.isNaN()) {
            Float.MAX_VALUE
        } else {
            abs(angleDelta(lastEmittedHeading, headingDeg.toFloat()))
        }

        val significantChange = delta >= MIN_DELTA_DEG
        val dueRefresh = sinceLast >= PERIODIC_REFRESH_MS
        val rateLimited = sinceLast < MIN_INTERVAL_MS

        if (!significantChange && !dueRefresh) return
        if (rateLimited) return

        lastEmitElapsedMs = now
        lastEmittedHeading = headingDeg.toFloat()

        val payload = mapOf<String, Any>(
            "heading" to headingDeg,
            "accuracy" to event.accuracy,
            "timestamp" to event.timestamp,
        )
        mainHandler.post { events.success(payload) }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    fun dispose() {
        if (listening) {
            sensorManager.unregisterListener(this)
            listening = false
        }
        sink = null
    }
}
