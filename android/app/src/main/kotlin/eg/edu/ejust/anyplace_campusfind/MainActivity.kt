package eg.edu.ejust.anyplace_campusfind

import eg.edu.ejust.anyplace_campusfind.positioning.PositioningBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var positioningBridge: PositioningBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        positioningBridge = PositioningBridge(flutterEngine.dartExecutor.binaryMessenger)
    }
}
