package eg.edu.ejust.anyplace_campusfind.positioning

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel bridge connecting Flutter Dart positioning service to native Kotlin engine.
 */
class PositioningBridge(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "eg.edu.ejust.anyplace_campusfind/positioning"
    }

    private val channel = MethodChannel(messenger, CHANNEL_NAME)

    init {
        channel.setMethodCallHandler(this)
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
                result.success(success)
            }

            "clearRadioMap" -> {
                PositioningEngine.clearRadioMap()
                result.success(true)
            }

            "getRadioMapInfo" -> {
                val info = PositioningEngine.getActiveInfo()
                result.success(info)
            }

            else -> {
                result.notImplemented()
            }
        }
    }
}
