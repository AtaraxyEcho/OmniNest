package com.omninest.app

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
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
                    val active = call.argument<Boolean>("active") ?: false
                    pipEligible = active
                    applyPipParams(active)
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

    // 构建 PiP 参数；Android 12+ 支持 auto-enter。
    private fun buildPipParams(autoEnter: Boolean): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return null
        }
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnter)
        }
        return builder.build()
    }

    private fun applyPipParams(videoActive: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val params = buildPipParams(autoEnter = videoActive) ?: return
        try {
            setPictureInPictureParams(params)
        } catch (_: IllegalStateException) {
            // 不在可更新 PiP 参数的状态（如已 finish）时忽略。
        }
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
        // Android 12+ 靠 auto-enter；更早版本在此手动进入。
        if (!pipEligible || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return
        }
        val params = buildPipParams(autoEnter = false) ?: return
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
