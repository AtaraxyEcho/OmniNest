import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

typedef ReaderSearchScanResult = ({List<int> offsets, bool truncated});

/// 全书搜索返回的命中和完整性状态。
typedef ReaderBookSearchResponse =
    ({List<ReaderBookSearchMatch> matches, bool truncated, bool incomplete});
typedef ReaderBookSearch =
    Future<ReaderBookSearchResponse> Function(
      String query,
      bool Function() isCancelled,
    );

/// 可定位的搜索命中，仅保留短上下文，避免结果列表持有章节全文。
class ReaderBookSearchMatch {
  const ReaderBookSearchMatch({
    required this.chapterId,
    required this.chapterTitle,
    required this.charOffset,
    required this.before,
    required this.match,
    required this.after,
  });

  factory ReaderBookSearchMatch.fromText({
    required String chapterId,
    required String chapterTitle,
    required String plainText,
    required int plainOffset,
    required int matchLength,
    required int charOffset,
  }) {
    final start = math.max(0, plainOffset - 36);
    final matchEnd = math.min(plainText.length, plainOffset + matchLength);
    final end = math.min(plainText.length, matchEnd + 36);
    return ReaderBookSearchMatch(
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      charOffset: charOffset,
      before: _normalizeBookSearchSnippet(
        plainText.substring(start, plainOffset),
        leading: start > 0,
      ),
      match: plainText.substring(plainOffset, matchEnd),
      after: _normalizeBookSearchSnippet(
        plainText.substring(matchEnd, end),
        trailing: end < plainText.length,
      ),
    );
  }

  final String chapterId;
  final String chapterTitle;
  final int charOffset;
  final String before;
  final String match;
  final String after;
}

String _normalizeBookSearchSnippet(
  String value, {
  bool leading = false,
  bool trailing = false,
}) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ');
  return '${leading ? '…' : ''}$normalized${trailing ? '…' : ''}';
}

/// 与桌面原型搜索结果上限一致。
const readerSearchMatchLimit = 60;

/// 原生端达到此长度后改用后台 isolate 扫描。
const readerSearchIsolateThreshold = 12000;

/// 扫描纯文本并返回原字符串码元偏移。
ReaderSearchScanResult scanReaderSearchChunk(
  (String plainText, String query, int limit) args,
) {
  final pattern = RegExp(RegExp.escape(args.$2), caseSensitive: false);
  final matches = <int>[];
  var truncated = false;
  for (final match in pattern.allMatches(args.$1)) {
    if (matches.length >= args.$3) {
      truncated = true;
      break;
    }
    matches.add(match.start);
  }
  return (offsets: matches, truncated: truncated);
}

/// 在书籍章节中搜索并返回可定位的章内字符偏移。
class ReaderFindPanel extends StatefulWidget {
  const ReaderFindPanel({
    required this.plainText,
    required this.settings,
    required this.onSelect,
    this.chapterTitleOf,
    this.searchBook,
    this.onSelectBookMatch,
    this.onQueryChanged,
    this.searchHint,
    super.key,
  });

  final String plainText;
  final ReaderViewSettings settings;
  final ValueChanged<int> onSelect;

  /// 查询词变化（已去首尾空白）；正文据此实时叠加命中高亮。
  final ValueChanged<String>? onQueryChanged;

  /// 可选：全局 offset → 章标题（窗口多章搜索时展示）。
  final String Function(int globalOffset)? chapterTitleOf;

  /// 桌面书籍搜索逐章读取，不预加载整本书到内存。
  final ReaderBookSearch? searchBook;
  final ValueChanged<ReaderBookSearchMatch>? onSelectBookMatch;

  /// 搜索框提示；默认「在书中搜索」。
  final String? searchHint;

  @override
  State<ReaderFindPanel> createState() => _ReaderFindPanelState();
}

class _ReaderFindPanelState extends State<ReaderFindPanel> {
  final TextEditingController _controller = TextEditingController();
  List<int> _matches = const [];
  List<ReaderBookSearchMatch>? _bookMatches;
  bool _truncated = false;
  bool _incomplete = false;
  bool _isSearching = false;
  Timer? _searchTimer;
  int _searchGeneration = 0;

  @override
  void didUpdateWidget(covariant ReaderFindPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 窗口文本会因布局失效重建而变化：旧 offset 会指向新文本的错误
    // 位置，须以当前查询重新匹配。
    if (oldWidget.plainText != widget.plainText) {
      _search(_controller.text);
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 在**原串**上匹配，拿到的下标才是可切片、可跳转的下标域。
  ///
  /// 旧写法把正文 `toLowerCase()` 之后再 indexOf：个别字符小写化会变长（`İ` →
  /// `i̇` 两个码元），整串下标整体前移，之后的切片高亮与跳转全部错位。
  /// `RegExp.escape` 保证用户输入的 `(`、`*` 等按字面量匹配。
  void _search(String query) {
    final trimmed = query.trim();
    final generation = ++_searchGeneration;
    _searchTimer?.cancel();
    if (trimmed.isEmpty || (widget.searchBook != null && trimmed.length < 2)) {
      setState(() {
        _matches = const [];
        _bookMatches = null;
        _truncated = false;
        _incomplete = false;
        _isSearching = false;
      });
      return;
    }
    setState(() {
      _matches = const [];
      _bookMatches = null;
      _truncated = false;
      _incomplete = false;
      _isSearching =
          widget.searchBook != null ||
          widget.plainText.length >= readerSearchIsolateThreshold;
    });
    if (widget.searchBook == null &&
        widget.plainText.length < readerSearchIsolateThreshold) {
      unawaited(_runSearch(trimmed, generation));
      return;
    }
    _searchTimer = Timer(MotionToken.fast, () {
      unawaited(_runSearch(trimmed, generation));
    });
  }

  Future<void> _runSearch(String query, int generation) async {
    final searchBook = widget.searchBook;
    if (searchBook != null) {
      final response = await searchBook(
        query,
        () => !mounted || generation != _searchGeneration,
      ).catchError((Object _) {
        return (
          matches: const <ReaderBookSearchMatch>[],
          truncated: false,
          incomplete: true,
        );
      });
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _bookMatches = response.matches;
        _truncated = response.truncated;
        _incomplete = response.incomplete;
        _isSearching = false;
      });
      return;
    }
    final text = widget.plainText;
    final result =
        !kIsWeb && text.length >= readerSearchIsolateThreshold
            ? await compute(scanReaderSearchChunk, (
              text,
              query,
              readerSearchMatchLimit,
            ))
            : scanReaderSearchChunk((text, query, readerSearchMatchLimit));
    if (!mounted || generation != _searchGeneration) return;
    setState(() {
      _matches = result.offsets;
      _truncated = result.truncated;
      _incomplete = false;
      _isSearching = false;
    });
  }

  TextSpan _highlightedSnippet(int offset, ReaderPanelColors colors) {
    final query = _controller.text.trim();
    final start = math.max(0, offset - 36);
    final end = math.min(widget.plainText.length, offset + query.length + 36);
    final before = widget.plainText.substring(start, offset);
    final matchEnd = math.min(widget.plainText.length, offset + query.length);
    final match = widget.plainText.substring(offset, matchEnd);
    final after = widget.plainText.substring(matchEnd, end);
    final normalStyle = TextStyle(
      color: colors.onSurface,
      fontSize: colors.isDarkGlass ? 13.5 : AppTypography.bodyMedium,
      height: 1.45,
    );
    return TextSpan(
      style: normalStyle,
      children: [
        TextSpan(text: _normalizeSnippetPart(before, leading: start > 0)),
        TextSpan(
          text: match,
          style: normalStyle.copyWith(
            color: colors.onSurface,
            backgroundColor: colors.accent.withValues(alpha: 0.22),
            fontWeight: FontWeight.w800,
          ),
        ),
        TextSpan(
          text: _normalizeSnippetPart(
            after,
            trailing: end < widget.plainText.length,
          ),
        ),
      ],
    );
  }

  TextSpan _bookHighlightedSnippet(
    ReaderBookSearchMatch result,
    ReaderPanelColors colors,
  ) {
    final normalStyle = TextStyle(
      color: colors.onSurface,
      fontSize: colors.isDarkGlass ? 13.5 : AppTypography.bodyMedium,
      height: 1.45,
    );
    return TextSpan(
      style: normalStyle,
      children: [
        TextSpan(text: result.before),
        TextSpan(
          text: result.match,
          style: normalStyle.copyWith(
            backgroundColor: colors.accent.withValues(alpha: 0.22),
            fontWeight: FontWeight.w800,
          ),
        ),
        TextSpan(text: result.after),
      ],
    );
  }

  String _normalizeSnippetPart(
    String value, {
    bool leading = false,
    bool trailing = false,
  }) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ');
    return '${leading ? '…' : ''}$normalized${trailing ? '…' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ReaderPanelColors.resolve(context, widget.settings.palette);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: TextField(
            controller: _controller,
            autofocus: true,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: AppTypography.bodyLarge,
            ),
            decoration: InputDecoration(
              hintText: widget.searchHint ?? l10n.readerSearchInBookHint,
              prefixIcon: Icon(
                Icons.search_rounded,
                color: colors.onSurfaceVariant,
              ),
              suffixIcon:
                  _controller.text.isEmpty
                      ? null
                      : IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        onPressed: () {
                          _controller.clear();
                          widget.onQueryChanged?.call('');
                          _search('');
                        },
                      ),
              suffixText:
                  _isSearching ||
                          _controller.text.trim().isEmpty ||
                          (widget.searchBook != null &&
                              _controller.text.trim().length < 2)
                      ? null
                      : l10n.readerSearchResultCount(
                        _bookMatches?.length ?? _matches.length,
                      ),
              suffixStyle: TextStyle(color: colors.onSurfaceVariant),
              hintStyle: TextStyle(color: colors.onSurfaceVariant),
              filled: true,
              fillColor: colors.controlFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              widget.onQueryChanged?.call(value.trim());
              _search(value);
            },
          ),
        ),
        if (_truncated || _incomplete)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _incomplete
                  ? l10n.readerSearchIncomplete
                  : l10n.readerSearchTruncated,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: AppTypography.bodySmall,
              ),
            ),
          ),
        Expanded(
          child:
              _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : _controller.text.trim().length >=
                          (widget.searchBook == null ? 1 : 2) &&
                      _matches.isEmpty &&
                      (_bookMatches?.isEmpty ?? true)
                  ? Center(
                    child: Text(
                      l10n.readerNoSearchResults,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: (_bookMatches?.length ?? 0) + _matches.length,
                    itemBuilder: (context, index) {
                      final bookMatches = _bookMatches;
                      if (bookMatches != null) {
                        final result = bookMatches[index];
                        return ListTile(
                          leading: SizedBox(
                            width: 32,
                            child: Text(
                              '${index + 1}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text.rich(
                            _bookHighlightedSnippet(result, colors),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            result.chapterTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: AppTypography.bodySmall,
                            ),
                          ),
                          onTap: () => widget.onSelectBookMatch?.call(result),
                        );
                      }
                      final offset = _matches[index];
                      final chapterTitle = widget.chapterTitleOf?.call(offset);
                      return ListTile(
                        leading: SizedBox(
                          width: 32,
                          child: Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text.rich(
                          _highlightedSnippet(offset, colors),
                          maxLines:
                              chapterTitle == null || chapterTitle.isEmpty
                                  ? 3
                                  : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle:
                            chapterTitle == null || chapterTitle.isEmpty
                                ? null
                                : Text(
                                  chapterTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: AppTypography.bodySmall,
                                  ),
                                ),
                        onTap: () => widget.onSelect(offset),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}
