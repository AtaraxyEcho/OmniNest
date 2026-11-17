# OmniNest Android release 的 R8 规则。
#
# Flutter Gradle 插件在 release 构建会附加 proguard-android-optimize.txt 与
# flutter_proguard_rules.pro（含 io.flutter.plugin 的 -dontwarn 与 FlutterPlugin
# 实现保留）。本文件只补两类插件自带规则覆盖不到的入口：按类名反射装载的
# 组件，以及依赖字段名稳定的序列化模型。

# 应用入口与 Flutter 插件注册表：注册表在部分宿主路径按类名反射装载。
-keep class com.omninest.app.MainActivity { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Flutter 引擎与 Android 适配层在收缩整包时的兜底告警抑制。
-dontwarn io.flutter.plugin.**
-dontwarn io.flutter.view.**
-dontwarn android.**

# audio_service：MediaBrowserService 与媒体键接收器由系统按类名实例化，
# 通知点击回跳也依赖类名稳定。
-keep class com.ryanheise.audioservice.** { *; }

# flutter_local_notifications：定时通知载荷经 Gson 反射序列化到
# SharedPreferences，模型字段名被改写会导致重启后恢复调度丢条目。
-keep class com.dexterous.** { *; }
-dontwarn com.google.gson.**
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations
-keepclassmembers,allowshrinking,allowobfuscation enum * {
    public static **[] VALUES;
    public static ** valueOf(java.lang.String);
}

# media_kit 的 libmpv JNI 绑定按固定类名注册原生方法，类名混淆后
# RegisterNatives 失败会在播放时才暴露。
-keep class io.mpv.** { *; }

# Kotlin 协程与注解在传递依赖中按可选类型引用，缺失只应告警。
-dontwarn kotlinx.coroutines.**
-dontwarn org.jetbrains.annotations.**
