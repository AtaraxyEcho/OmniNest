import 'package:flutter_riverpod/flutter_riverpod.dart';

const appearanceDeviceModeKey = 'appearance.device.theme_mode';
const appearanceDeviceFontScaleKey = 'appearance.device.font_scale';
const localeDeviceLanguageKey = 'locale.device.language';
const legacyGlobalThemeModeKey = 'global_theme_mode';
const legacyGlobalLanguageKey = 'global_language';

class AppBootstrapData {
  const AppBootstrapData({
    this.themeModeName = 'system',
    this.languageCode = 'zh',
    this.fontScaleName = 'followSystem',
  });

  final String themeModeName;
  final String languageCode;

  /// 设备本地字体档位名，冷启动预读避免首帧以默认档位渲染后跳变。
  final String fontScaleName;
}

final appBootstrapDataProvider = Provider<AppBootstrapData>((ref) {
  return const AppBootstrapData();
});
