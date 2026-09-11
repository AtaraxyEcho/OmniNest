import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 在当前已加载章节中搜索并返回字符偏移。
class ReaderFindPanel extends StatefulWidget {
  const ReaderFindPanel({
    required this.plainText,
    required this.settings,
    required this.onSelect,
    this.chapterTitleOf,
    this.searchHint,
    super.key,
  });

  final String plainText;
  final ReaderViewSettings settings;
  final ValueChanged<int> onSelect;

  /// 可选：全局 offset → 章标题（窗口多章搜索时展示）。
  final String Function(int globalOffset)? chapterTitleOf;

  /// 搜索框提示；默认「搜索当前章节」。
  final String? searchHint;

  @override
  State<ReaderFindPanel> createState() => _ReaderFindPanelState();
}

class _ReaderFindPanelState extends State<ReaderFindPanel> {
  final TextEditingController _controller = TextEditingController();
  List<int> _matches = const [];

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
    _controller.dispose();
    super.dispose();
  }

  void _search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      setState(() => _matches = const []);
      return;
    }
    final source = widget.plainText.toLowerCase();
    final matches = <int>[];
    var start = 0;
    while (matches.length < 100) {
      final index = source.indexOf(normalized, start);
      if (index < 0) {
        break;
      }
      matches.add(index);
      start = index + math.max(1, normalized.length);
    }
    setState(() => _matches = matches);
  }

  TextSpan _highlightedSnippet(int offset) {
    final query = _controller.text.trim();
    final start = math.max(0, offset - 36);
    final end = math.min(widget.plainText.length, offset + query.length + 36);
    final before = widget.plainText.substring(start, offset);
    final matchEnd = math.min(widget.plainText.length, offset + query.length);
    final match = widget.plainText.substring(offset, matchEnd);
    final after = widget.plainText.substring(matchEnd, end);
    final normalStyle = TextStyle(
      color: widget.settings.onSurfaceColor,
      fontSize: AppTypography.bodyMedium,
      height: 1.45,
    );
    return TextSpan(
      style: normalStyle,
      children: [
        TextSpan(text: _normalizeSnippetPart(before, leading: start > 0)),
        TextSpan(
          text: match,
          style: normalStyle.copyWith(
            color: widget.settings.onSurfaceColor,
            backgroundColor: widget.settings.accentColor.withValues(
              alpha: 0.22,
            ),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: TextField(
            controller: _controller,
            autofocus: true,
            style: TextStyle(color: widget.settings.onSurfaceColor),
            decoration: InputDecoration(
              hintText: widget.searchHint ?? l10n.readerSearchCurrentChapter,
              prefixIcon: Icon(
                Icons.search_rounded,
                color: widget.settings.onSurfaceVariantColor,
              ),
              suffixText:
                  _controller.text.trim().isEmpty
                      ? null
                      : l10n.readerSearchResultCount(_matches.length),
              suffixStyle: TextStyle(
                color: widget.settings.onSurfaceVariantColor,
              ),
              hintStyle: TextStyle(
                color: widget.settings.onSurfaceVariantColor,
              ),
              filled: true,
              fillColor: widget.settings.onSurfaceColor.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: _search,
          ),
        ),
        Expanded(
          child:
              _controller.text.trim().isNotEmpty && _matches.isEmpty
                  ? Center(
                    child: Text(
                      l10n.readerNoSearchResults,
                      style: TextStyle(
                        color: widget.settings.onSurfaceVariantColor,
                      ),
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: _matches.length,
                    itemBuilder: (context, index) {
                      final offset = _matches[index];
                      final chapterTitle = widget.chapterTitleOf?.call(offset);
                      return ListTile(
                        leading: SizedBox(
                          width: 32,
                          child: Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: widget.settings.accentColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text.rich(
                          _highlightedSnippet(offset),
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
                                    color:
                                        widget.settings.onSurfaceVariantColor,
                                    fontSize: AppTypography.labelSmall,
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
