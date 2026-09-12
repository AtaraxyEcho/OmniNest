import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 电池优化白名单引导：后台备份等长时任务依赖它免受系统省电拦截。
///
/// 仅 Android 生效，其它平台返回 null/跳过。
class BatteryOptimizationService {
  BatteryOptimizationService._();

  static const MethodChannel _channel = MethodChannel('omninest/battery');
  static BatteryOptimizationService? _instance;

  static BatteryOptimizationService instance() =>
      _instance ??= BatteryOptimizationService._();

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 当前是否已忽略电池优化；不支持的平台返回 null。
  Future<bool?> isIgnoringBatteryOptimizations() async {
    if (!isSupported) {
      return null;
    }
    try {
      return await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
    } on PlatformException {
      return null;
    }
  }

  /// 拉起系统"忽略电池优化"授权对话框。
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!isSupported) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
    } on PlatformException {
      // 低版本或定制 ROM 无该 Action 时忽略。
    }
  }
}
