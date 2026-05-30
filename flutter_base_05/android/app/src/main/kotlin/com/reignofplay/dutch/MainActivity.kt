package com.reignofplay.dutch

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DIRECT_SHARE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAppInstalled" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    result.success(DutchDirectShareHandler.isAppInstalled(this, packageName))
                }
                "resolveTikTokPackage" -> {
                    result.success(DutchDirectShareHandler.resolveTikTokPackage(this))
                }
                "shareToApp" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    val filePath = call.argument<String>("filePath") ?: ""
                    val mimeType = call.argument<String>("mimeType") ?: "*/*"
                    val text = call.argument<String>("text")
                    val status = DutchDirectShareHandler.shareToApp(
                        this,
                        packageName,
                        filePath,
                        mimeType,
                        text,
                    )
                    result.success(status)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        const val DIRECT_SHARE_CHANNEL = "com.reignofplay.dutch/direct_share"
    }
}
