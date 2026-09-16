package com.omninest.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.os.PowerManager
import android.util.Rational
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var pipChannel: MethodChannel? = null
    private var pipEligible = false
    private var readerVolumeChannel: MethodChannel? = null
    private var volumeKeyPagingEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "omninest/pip"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setVideoPlaybackActive" -> {
                    pipEligible = call.argument<Boolean>("active") ?: false
                    result.success(true)
                }
                "isInPipMode" -> result.success(isInPictureInPictureMode)
                else -> result.notImplemented()
            }
        }
        // 供 onUserLeaveHint 之外的生命周期回调向 Flutter 通知 PiP 状态。
        pipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "omninest/pip"
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "omninest/battery"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                    result.success(powerManager?.isIgnoringBatteryOptimizations(packageName) == true)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    val intent = Intent(
                        android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:$packageName")
                    )
                    startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        // 阅读器音量键翻页：开启后拦截音量键并转发方向，关闭后恢复系统音量。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "omninest/reader_volume"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    volumeKeyPagingEnabled = call.argument<Boolean>("enabled") ?: false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        readerVolumeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "omninest/reader_volume"
        )
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (volumeKeyPagingEnabled) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                        readerVolumeChannel?.invokeMethod(
                            "onVolumeKey",
                            if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down"
                        )
                    }
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!pipEligible || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .build()
        enterPictureInPictureMode(params)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }
}
