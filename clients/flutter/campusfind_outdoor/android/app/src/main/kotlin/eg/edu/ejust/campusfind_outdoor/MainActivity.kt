package eg.edu.ejust.campusfind_outdoor

import eg.edu.ejust.campusfind_outdoor.orientation.DeviceHeadingBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var headingBridge: DeviceHeadingBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        headingBridge = DeviceHeadingBridge(applicationContext)
        EventChannel(messenger, DeviceHeadingBridge.CHANNEL_NAME)
            .setStreamHandler(headingBridge)
    }

    override fun onDestroy() {
        headingBridge?.dispose()
        headingBridge = null
        super.onDestroy()
    }
}
