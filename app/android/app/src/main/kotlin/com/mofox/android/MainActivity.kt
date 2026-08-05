package com.mofox.android

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.PluginRegistry
import com.mofox.android.runtime.RuntimeBridgePlugin
import com.mofox.android.platform.PlatformGatewayPlugin

class MainActivity : FlutterActivity() {
    private val platformGateway = PlatformGatewayPlugin()
    private val runtimeBridge = RuntimeBridgePlugin()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        runtimeBridge.attach(flutterEngine, this)
        platformGateway.attach(flutterEngine, this)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        runtimeBridge.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (platformGateway.onActivityResult(requestCode, resultCode, data)) return
    }
}
