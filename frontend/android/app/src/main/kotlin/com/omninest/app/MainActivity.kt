package com.omninest.app

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var pipChannel: MethodChannel? = null
    private var pipEligible = false

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
