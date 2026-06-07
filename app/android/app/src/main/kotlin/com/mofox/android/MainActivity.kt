package com.mofox.android

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.mofox.android.runtime.RuntimeBridgePlugin
import com.mofox.android.platform.PlatformGatewayPlugin

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RuntimeBridgePlugin().attach(flutterEngine, this)
        PlatformGatewayPlugin().attach(flutterEngine, this)
    }
}
