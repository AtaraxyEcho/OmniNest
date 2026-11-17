import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart' show MediaQuery, Size;
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_preferences_controller.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/domain/reader_models.dart'
    show bookmarkAtChapter;
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 按壳层套用阅读默认：只有移动壳层把深色档的正文换成样例的衬线 19/1.85。
///
/// [hasSavedTypography] 为用户是否已经存过字号或行距：存过就不再覆盖，否则每次进书都会
/// 把读者自己拧过的排版打回样例档位。
@visibleForTesting
ReaderViewSettings applyReaderShellDefaults({
  required ReaderViewSettings loaded,
  required bool mobileShell,
  required bool hasSavedTypography,
}) {
  if (!mobileShell || hasSavedTypography) {
    return loaded;
  }
  return loaded.withMobileDefaults();
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
  String get currentChapterId;
  bool get isBookmarked;
  set isBookmarked(bool value);
  WindowChromeController get windowChromeController;
  WindowChromeLease? get windowChromeLease;
  set windowChromeLease(WindowChromeLease? value);

  ReaderProgressSnapshot? buildProgressSnapshot({double? progressOverride});

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
    // 用户已经存过字号或行距时尊重其选择，不能让样例档位每次进书都盖掉读者的设置。
    final resolved = applyReaderShellDefaults(
      loaded: loaded,
      mobileShell: shouldUseResponsiveMobileShell(
        mobilePlatform: isMobilePlatform,
        width: MediaQuery.sizeOf(context).width,
      ),
      hasSavedTypography:
          values.containsKey('fontSize') || values.containsKey('lineHeight'),
    );
    setState(() {
      settings = resolved;
    });
    applyImmersiveMode(resolved.immersiveMode);
  }

  /// 检查当前章节的书签状态。
  ///
  /// 按整书判存会把别章的书签算到本章头上，切章后高亮与取消目标都错位。
  Future<void> checkBookmarkState() async {
    if (!mounted) return;
    final snapshot = buildProgressSnapshot();
    final chapterId = snapshot?.chapterId ?? currentChapterId;
    final charOffset = snapshot?.charOffset ?? 0;
    try {
      final bookmarks = await ref
          .read(readerDataManagerProvider)
          .loadBookmarks(itemId);
      if (mounted) {
        setState(() {
          isBookmarked = bookmarks.any(
            (bookmark) => bookmarkAtChapter(
              bookmark,
              chapterId: chapterId,
              charOffset: charOffset,
            ),
          );
        });
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        readerDebugLog('ReaderView: bookmark state query failed: $e');
      }
    }
  }
}
