import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_preferences_controller.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

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
    final resolved =
        values.isEmpty
            ? ReaderViewSettings()
            : ReaderViewSettings.fromJson(values);
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
