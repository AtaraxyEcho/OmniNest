part of 'reader_view_page_builders.dart';

/// 正文内链接点击与锚点定位。
extension ReaderViewPageBuildersLinks on ReaderViewPageBuilders {
  void handleReaderLinkTap(String href) {
    final link = href.trim();
    if (link.isEmpty) {
      return;
    }
    if (_isExternalReaderHref(link)) {
      _showUnsupportedLinkSnackBar();
      return;
    }
    final target = _findLinkedTarget(link);
    if (target != null) {
      if (target.chapterId == currentChapterId) {
        _restoreAnchorInCurrentChapter(target.anchor);
      } else {
        unawaited(
          switchToChapter(
            target.chapterId,
            intent: ReaderChapterNavigationIntent.anchor(
              target.anchor,
              offerReturn: true,
            ),
          ),
        );
      }
      return;
    }
    _showUnsupportedLinkSnackBar();
  }

  void _showUnsupportedLinkSnackBar() {
    final message = AppLocalizations.of(context).readerUnsupportedLink;
    showReaderSnackBar(context, message);
  }

  _ReaderLinkTarget? _findLinkedTarget(String href) {
    final chapters = contentLoader?.allChapters ?? [];
    if (chapters.isEmpty) {
      return null;
    }
    final anchor = _extractReaderAnchor(href);
    final normalizedHref = _resolveReaderHref(href);
    if (normalizedHref.isEmpty) {
      return _ReaderLinkTarget(currentChapterId, anchor);
    }
    for (final chapter in chapters) {
      final contentPath = chapter.contentPath;
      if (contentPath == null || contentPath.isEmpty) {
        continue;
      }
      final normalizedPath = _normalizeReaderHref(contentPath);
      if (normalizedPath == normalizedHref ||
          normalizedPath.endsWith('/$normalizedHref') ||
          normalizedHref.endsWith('/$normalizedPath')) {
        return _ReaderLinkTarget(chapter.id, anchor);
      }
    }
    return null;
  }

  /// 解析正文链接：相对路径以当前章节目录为基准消解 `.` 与 `..`。
  ///
  /// EPUB 正文常用 `../Text/chapter02.xhtml#fn1` 这类跨目录写法，只剥前导
  /// `./` 会让它永远匹配不到章节 contentPath，被误判为不支持的链接。
  String _resolveReaderHref(String href) {
    final normalized = _normalizeReaderHref(href);
    if (normalized.isEmpty || normalized.startsWith('/')) {
      return _removeDotSegments(normalized);
    }
    final currentPath = _currentChapterContentPath();
    if (currentPath == null || currentPath.isEmpty) {
      return _removeDotSegments(normalized);
    }
    final normalizedCurrent = _normalizeReaderHref(currentPath);
    final slashIndex = normalizedCurrent.lastIndexOf('/');
    final baseDir =
        slashIndex >= 0 ? normalizedCurrent.substring(0, slashIndex + 1) : '';
    return _removeDotSegments('$baseDir$normalized');
  }

  String? _currentChapterContentPath() {
    for (final chapter in contentLoader?.allChapters ?? const []) {
      if (chapter.id == currentChapterId) {
        return chapter.contentPath;
      }
    }
    return null;
  }

  String _removeDotSegments(String path) {
    final segments = <String>[];
    final parts = path.split('/');
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      if (part.isEmpty || part == '.') {
        if (index == 0 && part.isEmpty) {
          segments.add('');
        }
        continue;
      }
      if (part == '..') {
        if (segments.isNotEmpty &&
            segments.last != '' &&
            segments.last != '..') {
          segments.removeLast();
        }
        continue;
      }
      segments.add(part);
    }
    return segments.join('/');
  }

  String _normalizeReaderHref(String href) {
    var value = lenientDecodeComponent(href.trim());
    final hashIndex = value.indexOf('#');
    if (hashIndex >= 0) {
      value = value.substring(0, hashIndex);
    }
    final queryIndex = value.indexOf('?');
    if (queryIndex >= 0) {
      value = value.substring(0, queryIndex);
    }
    value = value.replaceAll('\\', '/');
    while (value.startsWith('./')) {
      value = value.substring(2);
    }
    return value;
  }

  bool _isExternalReaderHref(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null) {
      return false;
    }
    // 所有带 scheme 的地址（含 file:）都不是章节内相对路径，不能进入匹配循环。
    return uri.hasScheme;
  }

  String? _extractReaderAnchor(String href) {
    final hashIndex = href.indexOf('#');
    if (hashIndex < 0 || hashIndex == href.length - 1) {
      return null;
    }
    return lenientDecodeComponent(href.substring(hashIndex + 1));
  }

  void _restoreAnchorInCurrentChapter(String? anchor) {
    final charOffset = resolveAnchorCharOffset(currentChapterId, anchor);
    if (charOffset == null) {
      return;
    }
    isRestoringProgress = true;
    pendingRestoreCharOffset = charOffset;
    if (mounted) {
      _updateState(() {});
    }
  }
}
