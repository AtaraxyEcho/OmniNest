import 'package:omninest/features/backdrop/domain/app_backdrop.dart';

/// 背景设置与用户偏好 JSON(scope=backdrop)之间的映射。
/// 字段名与方案 §31 保持一致,服务端为事实来源。
class AppBackdropSettingsJson {
  const AppBackdropSettingsJson._();

  /// 从偏好快照解析设置;缺失键回落到 [fallback] 的当前值。
  static AppBackdropSettings fromPreferences(
    Map<String, dynamic> json,
    AppBackdropSettings fallback,
  ) {
    return AppBackdropSettings(
      enabled: _optBool(json['enabled']) ?? fallback.enabled,
      selectedBackdropId:
          _optString(json['selectedAssetId']) ?? fallback.selectedBackdropId,
      separateDeviceBackdrops:
          _optBool(json['separateDeviceBackdrops']) ??
          fallback.separateDeviceBackdrops,
      desktopBackdropId:
          _optString(json['desktopAssetId']) ?? fallback.desktopBackdropId,
      mobileBackdropId:
          _optString(json['mobileAssetId']) ?? fallback.mobileBackdropId,
      fit: AppBackdropFit.fromValue(
        json['fit']?.toString() ?? fallback.fit.value,
      ),
      alignment: AppBackdropAlignment.fromValue(
        json['alignment']?.toString() ?? fallback.alignment.value,
      ),
      dimAmount: _optDouble(json['dimAmount']) ?? fallback.dimAmount,
      blurAmount: _optDouble(json['blurAmount']) ?? fallback.blurAmount,
      videoMuted: _optBool(json['videoMuted']) ?? fallback.videoMuted,
    );
  }

  /// 将设置展开为 PATCH changes 全量键值。
  static Map<String, dynamic> toChanges(AppBackdropSettings settings) {
    return {
      'enabled': settings.enabled,
      'selectedAssetId': settings.selectedBackdropId,
      'separateDeviceBackdrops': settings.separateDeviceBackdrops,
      'desktopAssetId': settings.desktopBackdropId,
      'mobileAssetId': settings.mobileBackdropId,
      'fit': settings.fit.value,
      'alignment': settings.alignment.value,
      'dimAmount': settings.dimAmount,
      'blurAmount': settings.blurAmount,
      'videoMuted': settings.videoMuted,
    };
  }

  static String? _optString(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static bool? _optBool(Object? value) {
    return value is bool ? value : null;
  }

  static double? _optDouble(Object? value) {
    return value is num ? value.toDouble() : null;
  }
}
