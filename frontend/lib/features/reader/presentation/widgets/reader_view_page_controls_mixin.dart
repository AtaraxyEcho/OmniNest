import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_navigation.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 阅读页章节面板、控制栏和键盘事件逻辑。
mixin ReaderViewPageControlsMixin on ConsumerState<ReaderViewPage> {
  static const hideDelay = Duration(seconds: 3);

  Timer? get hideTimer;
  set hideTimer(Timer? value);
  bool get showControls;
  set showControls(bool value);
  bool get isHoveringControls;
  set isHoveringControls(bool value);
  String? get cachedPlainText;
  set cachedPlainText(String? value);
  String? get cachedContentSource;
  set cachedContentSource(String? value);
  String get itemId;
  bool get exitRequested;
  set exitRequested(bool value);
  Future<void> switchToChapter(
    String chapterId, {
    required ReaderChapterNavigationIntent intent,
  });

  /// 章节选中回调。
  void onChapterSelected(String chapterId) {
    unawaited(
      switchToChapter(
        chapterId,
        intent: const ReaderChapterNavigationIntent.start(offerReturn: true),
      ),
    );
  }

  /// 获取 HTML 内容的纯文本（带缓存）。
  String getPlainText(String htmlContent) {
    if (cachedContentSource == htmlContent && cachedPlainText != null) {
      return cachedPlainText!;
    }
    cachedContentSource = htmlContent;
    cachedPlainText = stripHtml(htmlContent);
    return cachedPlainText!;
  }

  /// 返回条目详情页，并避免在当前帧销毁仍在处理选择事件的阅读树。
  void safePop() {
    if (kDebugMode) {
      readerDebugLog(
        'safePop: mounted=$mounted, context.mounted=${context.mounted}',
      );
    }
    if (!mounted || !context.mounted || exitRequested) {
      return;
    }
    exitRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !context.mounted) {
        return;
      }
      // 阅读页由条目详情 push 进来，pop 才能保留来路（首页、媒体库或
      // 阅读空间里的上一级）；go 会把整条栈换成详情页，退出阅读后系统
      // 返回就落在栈底，表现为直接退出应用。深链直入没有可弹层时才回落。
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/reader/items/$itemId');
      }
    });
  }

  /// 切换控制栏显示状态。
  void toggleControls() {
    setState(() => showControls = !showControls);
    if (showControls) startHideTimer();
  }

  /// 启动控制栏自动隐藏计时器。
  void startHideTimer() {
    hideTimer?.cancel();
    if (isHoveringControls) return;
    hideTimer = Timer(hideDelay, () {
      if (mounted && !isHoveringControls) {
        setState(() => showControls = false);
      }
    });
  }

  /// 鼠标悬停/移出控件栏时调用。
  void onHoverControls(bool hovering) {
    if (isHoveringControls == hovering) return;
    isHoveringControls = hovering;
    if (hovering) {
      hideTimer?.cancel();
    } else {
      startHideTimer();
    }
  }
}
