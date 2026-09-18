import 'package:flutter/services.dart';

/// 阅读器支持的统一用户命令。
enum ReaderCommand {
  closeLayer,
  toggleContents,
  toggleBookmark,
  openSearch,
  openAnnotations,
  toggleImmersive,
  toggleFullscreen,
  showShortcuts,
  increaseFont,
  decreaseFont,
  resetTypography,
  nextPage,
  previousPage,
  nextViewport,
  previousViewport,
  scrollForward,
  scrollBackward,
  chapterStart,
  chapterEnd,
  nextChapter,
  previousChapter,
  toggleReadingMode,
}

/// 阅读器当前执行快捷键所需的最小上下文。
enum ReaderShortcutMode { textScroll, textPage, comicScroll, comicPage }

/// 将按键解析为与具体阅读实现无关的命令。
class ReaderShortcutResolver {
  const ReaderShortcutResolver();

  ReaderCommand? resolve({
    required LogicalKeyboardKey key,
    required ReaderShortcutMode mode,
    bool shiftPressed = false,
    bool controlPressed = false,
    bool isRtl = false,
    bool textInputFocused = false,
    bool imageZoomed = false,
  }) {
    final isTextMode =
        mode == ReaderShortcutMode.textScroll ||
        mode == ReaderShortcutMode.textPage;
    if (textInputFocused) {
      return key == LogicalKeyboardKey.escape ? ReaderCommand.closeLayer : null;
    }
    if (key == LogicalKeyboardKey.escape) {
      return ReaderCommand.closeLayer;
    }
    if (isTextMode && controlPressed && key == LogicalKeyboardKey.keyF) {
      return ReaderCommand.openSearch;
    }
    if (key == LogicalKeyboardKey.keyT) {
      return ReaderCommand.toggleContents;
    }
    if (isTextMode && key == LogicalKeyboardKey.keyB) {
      return ReaderCommand.toggleBookmark;
    }
    if (isTextMode && key == LogicalKeyboardKey.keyN) {
      return ReaderCommand.openAnnotations;
    }
    if (key == LogicalKeyboardKey.keyF) {
      return ReaderCommand.toggleImmersive;
    }
    // F11 不在此映射：app.dart 全局按键处理器统一分发无边框全屏，
    // 页面级再绑定会在同一按键上双重触发（焦点树与硬件层先后执行）。
    if (shiftPressed && key == LogicalKeyboardKey.slash) {
      return ReaderCommand.showShortcuts;
    }
    if (isTextMode) {
      final typography = _resolveTypography(key);
      if (typography != null) {
        return typography;
      }
    }
    if ((mode == ReaderShortcutMode.comicPage ||
            mode == ReaderShortcutMode.comicScroll) &&
        key == LogicalKeyboardKey.keyM) {
      return ReaderCommand.toggleReadingMode;
    }

    return switch (mode) {
      ReaderShortcutMode.textScroll => _resolveTextScroll(key, shiftPressed),
      ReaderShortcutMode.textPage => _resolveTextPage(key, shiftPressed),
      ReaderShortcutMode.comicScroll => _resolveComicScroll(key, shiftPressed),
      ReaderShortcutMode.comicPage =>
        imageZoomed ? null : _resolveComicPage(key, shiftPressed, isRtl),
    };
  }

  ReaderCommand? _resolveTypography(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add) {
      return ReaderCommand.increaseFont;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      return ReaderCommand.decreaseFont;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      return ReaderCommand.resetTypography;
    }
    return null;
  }

  ReaderCommand? _resolveTextScroll(LogicalKeyboardKey key, bool shiftPressed) {
    if (key == LogicalKeyboardKey.space) {
      return shiftPressed
          ? ReaderCommand.previousViewport
          : ReaderCommand.nextViewport;
    }
    return switch (key) {
      LogicalKeyboardKey.pageDown => ReaderCommand.nextViewport,
      LogicalKeyboardKey.pageUp => ReaderCommand.previousViewport,
      LogicalKeyboardKey.arrowDown => ReaderCommand.scrollForward,
      LogicalKeyboardKey.arrowUp => ReaderCommand.scrollBackward,
      LogicalKeyboardKey.arrowRight => ReaderCommand.nextChapter,
      LogicalKeyboardKey.arrowLeft => ReaderCommand.previousChapter,
      LogicalKeyboardKey.home => ReaderCommand.chapterStart,
      LogicalKeyboardKey.end => ReaderCommand.chapterEnd,
      _ => null,
    };
  }

  ReaderCommand? _resolveTextPage(LogicalKeyboardKey key, bool shiftPressed) {
    if (key == LogicalKeyboardKey.space) {
      return shiftPressed ? ReaderCommand.previousPage : ReaderCommand.nextPage;
    }
    return switch (key) {
      LogicalKeyboardKey.pageDown ||
      LogicalKeyboardKey.arrowRight => ReaderCommand.nextPage,
      LogicalKeyboardKey.pageUp ||
      LogicalKeyboardKey.arrowLeft => ReaderCommand.previousPage,
      LogicalKeyboardKey.home => ReaderCommand.chapterStart,
      LogicalKeyboardKey.end => ReaderCommand.chapterEnd,
      _ => null,
    };
  }

  ReaderCommand? _resolveComicScroll(
    LogicalKeyboardKey key,
    bool shiftPressed,
  ) {
    if (key == LogicalKeyboardKey.space) {
      return shiftPressed
          ? ReaderCommand.previousViewport
          : ReaderCommand.nextViewport;
    }
    return switch (key) {
      LogicalKeyboardKey.pageDown => ReaderCommand.nextViewport,
      LogicalKeyboardKey.pageUp => ReaderCommand.previousViewport,
      LogicalKeyboardKey.arrowDown => ReaderCommand.scrollForward,
      LogicalKeyboardKey.arrowUp => ReaderCommand.scrollBackward,
      LogicalKeyboardKey.home => ReaderCommand.chapterStart,
      LogicalKeyboardKey.end => ReaderCommand.chapterEnd,
      _ => null,
    };
  }

  ReaderCommand? _resolveComicPage(
    LogicalKeyboardKey key,
    bool shiftPressed,
    bool isRtl,
  ) {
    if (key == LogicalKeyboardKey.space) {
      return shiftPressed ? ReaderCommand.previousPage : ReaderCommand.nextPage;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      return ReaderCommand.nextPage;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      return ReaderCommand.previousPage;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return isRtl ? ReaderCommand.previousPage : ReaderCommand.nextPage;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return isRtl ? ReaderCommand.nextPage : ReaderCommand.previousPage;
    }
    if (key == LogicalKeyboardKey.home) {
      return ReaderCommand.chapterStart;
    }
    if (key == LogicalKeyboardKey.end) {
      return ReaderCommand.chapterEnd;
    }
    return null;
  }
}

/// 限制离散翻页和模式切换命令的触发频率。
class ReaderCommandGate {
  ReaderCommandGate({this.interval = const Duration(milliseconds: 220)});

  final Duration interval;
  DateTime _lastAccepted = DateTime.fromMillisecondsSinceEpoch(0);

  bool accept([DateTime? now]) {
    final current = now ?? DateTime.now();
    if (current.difference(_lastAccepted) < interval) {
      return false;
    }
    _lastAccepted = current;
    return true;
  }
}
