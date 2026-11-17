import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/platform/desktop/desktop_tray_service.dart';

/// 桌面托盘文案跟随应用语言：语言变化时按 ARB 刷新托盘右键菜单。
///
/// 初始菜单由桌面壳层按持久化设备语言生成，本绑定只负责运行期切换；
/// 仅桌面平台生效，其余平台为空实现。在应用根 Provider 中 watch 一次持续生效。
final desktopTrayLocaleBindingProvider = Provider<void>((ref) {
  if (!isDesktopPlatform) {
    return;
  }
  ref.listen(localeControllerProvider, (_, languageCode) {
    unawaited(DesktopTrayService.instance?.applyLanguage(languageCode));
  });
});
