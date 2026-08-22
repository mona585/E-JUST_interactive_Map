package eg.edu.ejust.anyplace_campusfind

import eg.edu.ejust.anyplace_campusfind.orientation.DeviceHeadingBridge
import eg.edu.ejust.anyplace_campusfind.positioning.PositioningBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var positioningBridge: PositioningBridge? = null
    private var headingBridge: DeviceHeadingBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        positioningBridge = PositioningBridge(messenger, applicationContext)

        headingBridge = DeviceHeadingBridge(applicationContext)
        EventChannel(messenger, DeviceHeadingBridge.CHANNEL_NAME)
            .setStreamHandler(headingBridge)
    }

    override fun onDestroy() {
        positioningBridge?.dispose()
        positioningBridge = null
        headingBridge?.dispose()
        headingBridge = null
        super.onDestroy()
    }
}
