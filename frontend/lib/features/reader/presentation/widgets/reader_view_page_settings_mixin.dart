import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart' show MediaQuery, Size;
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_preferences_controller.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 按壳层套用阅读默认：只有移动壳层把深色档的正文换成样例的衬线 19/1.85。
@visibleForTesting
ReaderViewSettings applyReaderShellDefaults({
  required ReaderViewSettings loaded,
  required bool mobileShell,
}) {
  return mobileShell ? loaded.withMobileDefaults() : loaded;
}

/// 阅读页设置与状态初始化逻辑。
mixin ReaderViewPageSettingsMixin on ConsumerState<ReaderViewPage> {
  ReaderContentLoader? get contentLoader;
  ReaderViewSettings get settings;
  set settings(ReaderViewSettings value);
  Timer? get persistTimer;
  set persistTimer(Timer? value);
  bool get isPageMode;
  String get itemId;
  bool get isBookmarked;
  set isBookmarked(bool value);
  WindowChromeController get windowChromeController;
  WindowChromeLease? get windowChromeLease;
  set windowChromeLease(WindowChromeLease? value);

  void repaginateForViewportChange(Size newSize);

  /// 应用沉浸模式系统 UI 设置。
  void applyImmersiveMode(bool immersive) {
    if (immersive) {
      windowChromeLease ??= windowChromeController.acquireImmersive(
        owner: 'reader.view.$itemId',
      );
      return;
    }
    windowChromeLease?.release();
    windowChromeLease = null;
  }

  /// 防抖持久化阅读设置。
  void persistSettings(ReaderViewSettings settings) {
    persistTimer?.cancel();
    persistTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      ref.read(readerPreferencesProvider.notifier).save(settings.toJson());
    });
  }

  /// 视口尺寸变化回调。
  void onViewportChanged(Size newSize) {
    if (contentLoader == null || !isPageMode) return;
    repaginateForViewportChange(newSize);
  }

  /// 从用户偏好快照加载阅读设置。
  Future<void> loadSettings() async {
    final values = await ref.read(readerPreferencesProvider.future);
    if (!mounted) return;
    final loaded =
        values.isEmpty
            ? ReaderViewSettings()
            : ReaderViewSettings.fromJson(values);
    // 移动壳层默认：深色档正文换成衬线 19/1.85（样例 ReaderFocus 书体）；判据与
    // 阅读页其余壳层分叉同源，桌面宽窗浏览器不跟着换档。
    // 用户已显式保存非默认主题时尊重其选择。
    final resolved = applyReaderShellDefaults(
      loaded: loaded,
      mobileShell: shouldUseResponsiveMobileShell(
        mobilePlatform: isMobilePlatform,
        width: MediaQuery.sizeOf(context).width,
      ),
    );
    setState(() {
      settings = resolved;
    });
    applyImmersiveMode(resolved.immersiveMode);
  }

  /// 检查当前书籍的书签状态。
  Future<void> checkBookmarkState() async {
    if (!mounted) return;
    try {
      final bookmarks = await ref
          .read(readerDataManagerProvider)
          .loadBookmarks(itemId);
      if (mounted) {
        setState(() {
          isBookmarked = bookmarks.isNotEmpty;
        });
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        readerDebugLog('ReaderView: bookmark state query failed: $e');
      }
    }
  }
}
