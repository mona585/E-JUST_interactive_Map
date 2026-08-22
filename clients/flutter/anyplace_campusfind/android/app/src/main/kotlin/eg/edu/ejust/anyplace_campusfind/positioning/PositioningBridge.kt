package eg.edu.ejust.anyplace_campusfind.positioning

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform bridge exposing the positioning engine to Dart.
 *
 * MethodChannel `eg.edu.ejust.anyplace_campusfind/positioning`:
 *   - loadRadioMap(text, buid, floor) -> Boolean (also starts scanning on success)
 *   - clearRadioMap() -> Boolean      (stops scanning)
 *   - getRadioMapInfo() -> Map?
 *
 * EventChannel `eg.edu.ejust.anyplace_campusfind/position_stream`:
 *   emits estimate maps:
 *   { latitude, longitude, buid, floor, matchedAps, totalAps, durationMs, timestamp, status }
 */
class PositioningBridge(
    messenger: BinaryMessenger,
    private val context: Context
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL_NAME = "eg.edu.ejust.anyplace_campusfind/positioning"
        const val EVENT_CHANNEL_NAME = "eg.edu.ejust.anyplace_campusfind/position_stream"
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL_NAME)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL_NAME)
    private val wifiScanner = WifiScanner(context)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)

        PositioningEngine.setListener(object : PositioningEngine.PositionUpdateListener {
            override fun onPositionEstimated(estimate: NativePositionEstimate) {
                val payload = mapOf<String, Any?>(
                    "latitude" to estimate.latitude,
                    "longitude" to estimate.longitude,
                    "buid" to estimate.buid,
                    "floor" to estimate.floor,
                    "matchedAps" to estimate.matchedAps,
                    "totalAps" to estimate.totalAps,
                    "durationMs" to estimate.durationMs,
                    "timestamp" to estimate.timestamp,
                    "status" to estimate.status
                )
                mainHandler.post { eventSink?.success(payload) }
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadRadioMap" -> {
                val text = call.argument<String>("text") ?: ""
                val buid = call.argument<String>("buid") ?: ""
                val floor = call.argument<String>("floor") ?: ""

                if (text.isEmpty()) {
                    result.error("INVALID_ARGUMENT", "RadioMap text cannot be empty", null)
                    return
                }

                val success = PositioningEngine.loadRadioMapText(text, buid, floor)
                if (success) {
                    wifiScanner.startScanning()
                } else {
                    wifiScanner.stopScanning()
                }
                result.success(success)
            }

            "clearRadioMap" -> {
                PositioningEngine.clearRadioMap()
                wifiScanner.stopScanning()
                result.success(true)
            }

            "getRadioMapInfo" -> result.success(PositioningEngine.getActiveInfo())

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        wifiScanner.stopScanning()
        PositioningEngine.setListener(null)
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }
}
