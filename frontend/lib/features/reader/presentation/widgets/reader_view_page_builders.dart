import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/application/reader_chapter_load_coordinator.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_navigation.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_view.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_locator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_position_tracker.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_return_to_progress_control.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_content.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/presentation/widgets/scroll_restore.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

part 'reader_view_page_builders_schedule.dart';
part 'reader_view_page_builders_content.dart';
part 'reader_view_page_builders_links.dart';
part 'reader_view_page_builders_restore.dart';
part 'reader_view_page_builders_return.dart';
part 'reader_view_page_builders_callbacks.dart';

/// reader_view_page.dart 的构建方法 mixin。
///
/// 通过 getter/setter 访问 State 字段，避免私有成员访问限制。
mixin ReaderViewPageBuilders on ConsumerState<ReaderViewPage> {
  /// 扩展方法使用的状态更新入口：mounted 检查后调用 setState。
  void _updateState(VoidCallback update) {
    if (mounted) {
      setState(update);
    }
  }

  bool _readerRebuildScheduled = false;
  bool _viewportUpdateScheduled = false;
  Size? _pendingViewportSize;
  bool _pageNavigatorWarmupScheduled = false;
  String? _pageCountWarmupChapterId;
  bool _scrollRestoreScheduled = false;
  bool _pageRestoreScheduled = false;
  ReaderProgressSnapshot? _pendingProgressSnapshot;
  bool _progressSnapshotApplyScheduled = false;

  // ── State 字段访问器（由 State 实现） ──
  ReaderContentLoader? get contentLoader;
  ReaderPositionTracker get positionTracker;
  ScrollController get scrollController;
  ScrollRestore get restore;
  ReaderViewSettings get settings;
  String get currentChapterId;
  bool get isPageMode;
  int get pageModePage;
  set pageModePage(int value);
  ValueNotifier<int> get pageCountNotifier;
  bool get isRestoringProgress;
  set isRestoringProgress(bool value);
  DateTime get restoreSilenceUntil;
  set restoreSilenceUntil(DateTime value);
  double get scrollProgress;
  set scrollProgress(double value);
  double? get pendingChapterProgress;
  set pendingChapterProgress(double? value);
  int? get pendingRestoreCharOffset;
  set pendingRestoreCharOffset(int? value);
  DateTime get lastPointerDownTime;
  set lastPointerDownTime(DateTime value);
  Size? get pageViewportSize;
  set pageViewportSize(Size? value);
  bool get showReturnControl;
  bool get showControls;
  bool get modeSwitchInProgress;
  set modeSwitchInProgress(bool value);
  int? get modeSwitchAnchor;
  set modeSwitchAnchor(int? value);
  int get restoreTargetCharOffset;
  set restoreTargetCharOffset(int value);
  bool get isSwitchingChapter;
  bool get isLoadingChapter;
  bool get selectionActive;
  ReaderChapterLoadCoordinator get chapterLoadCoordinator;
  ReaderPageLocator get pageLocator;
  dynamic get annotationHandler;
  String get itemId;
  ReaderPageTurnController get pageTurnController;

  // ── 跨 mixin 方法（由 State 实现） ──
  void dismissReturnSnackBar();
  void updateProgressFromPage();
  void onAnimationComplete();
  void tryNavigateChapter(int offset);
  void toggleControls();
  void returnToOriginalProgress();
  void onViewportChanged(Size newSize);
  Future<int?> findPageByCharOffset(ChapterData chapterData, int charOffset);
  Future<void> switchToChapter(
    String chapterId, {
    required ReaderChapterNavigationIntent intent,
  });
  void scheduleLocalProgressSave({
    required double chapterProgress,
    required int charOffset,
    required String mode,
  });
  void onReaderSelectionActive(bool active);
  DateTime? get lastAppliedProgressAt;
  void applyProgressSnapshot(ReaderProgressSnapshot snapshot);
  void prefetchNextChapterAtBoundary(int pageIndex);

  /// 反向章界回退：用户在窗口顶部继续上滚时回退到上一章末尾，
  /// 由 ReaderViewPageInteractionMixin 实现并在滚动内容越界时调用。
  void handleBackwardChapterOverscroll();

  // ── 页面尺寸 ──

  double computePageWidth() {
    final viewport = pageViewportSize;
    final size =
        viewport != null && viewport.width.isFinite
            ? viewport
            : MediaQuery.sizeOf(context);
    return ReaderControlLayout.resolve(
      viewport: size,
      fontSize: settings.fontSize,
      textScale: MediaQuery.textScalerOf(context).scale(1),
    ).textColumnWidth;
  }

  double computePageHeight() {
    final chromeLayout = ReaderChromeLayout.resolve(
      immersiveMode: settings.immersiveMode,
      isPageMode: isPageMode,
    );
    final viewport = pageViewportSize;
    if (viewport != null && viewport.height.isFinite) {
      final available = viewport.height - chromeLayout.chapterHeaderReserve - 1;
      return available > 1 ? available : 1;
    }
    final size = MediaQuery.sizeOf(context);
    final topInset =
        settings.immersiveMode ? 0.0 : MediaQuery.viewPaddingOf(context).top;
    final available =
        size.height - topInset - chromeLayout.viewportVerticalReserve;
    final contentHeight = available - chromeLayout.chapterHeaderReserve - 1;
    return contentHeight > 1 ? contentHeight : 1;
  }

  double get viewportAnchorY {
    final size = MediaQuery.sizeOf(context);
    final topInset =
        settings.immersiveMode ? 0.0 : MediaQuery.viewPaddingOf(context).top;
    final chromeLayout = ReaderChromeLayout.resolve(
      immersiveMode: settings.immersiveMode,
      isPageMode: isPageMode,
    );
    return (size.height - topInset - chromeLayout.viewportVerticalReserve) *
        0.25;
  }

  int computePageCharOffset(int pageIndex) {
    final slice = contentLoader?.computePage(
      chapterId: currentChapterId,
      settings: settings,
      pageWidth: computePageWidth(),
      pageHeight: computePageHeight(),
      pageIndex: pageIndex,
      textScale: MediaQuery.textScalerOf(context).scale(1.0),
    );
    return slice?.startCharOffset ?? 0;
  }

  PageTurnMode parsePageTurnMode(String mode) {
    return switch (mode) {
      'cover' => PageTurnMode.cover,
      'fade' => PageTurnMode.fade,
      _ => PageTurnMode.slide,
    };
  }

  int? resolveAnchorCharOffset(String chapterId, String? anchor) {
    if (anchor == null || anchor.isEmpty) {
      return 0;
    }
    final data = contentLoader?.getByChapterId(chapterId);
    final htmlContent = data?.content.content;
    if (htmlContent == null || htmlContent.isEmpty) {
      return null;
    }
    final anchorOffset = _findAnchorHtmlOffset(htmlContent, anchor);
    if (anchorOffset == null) {
      return null;
    }
    final prefix = htmlContent.substring(0, anchorOffset);
    final plainPrefix = stripHtml(prefix);
    return plainPrefix.length.clamp(0, data!.totalChars).toInt();
  }

  int? _findAnchorHtmlOffset(String html, String anchor) {
    final escaped = RegExp.escape(anchor);
    final pattern = RegExp(
      '\\s(?:id|name)\\s*=\\s*["\\\']$escaped["\\\']',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(html);
    return match?.start;
  }
}
