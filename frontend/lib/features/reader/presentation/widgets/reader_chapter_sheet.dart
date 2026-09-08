import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/reader_l10n_helpers.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 章节列表底部弹窗。
///
/// 参考微信读书 / Kindle 设计：
/// - 顶部拖拽手柄 + 标题栏（固定）
/// - 可滚动章节列表
/// - 多级缩进 + 展开/折叠
/// - 当前章节高亮
/// - 点击跳转 / 点击展开
Future<void> showReaderChapterSheet({
  required BuildContext context,
  required ReaderItemDetail detail,
  required String currentChapterId,
  required String itemId,
  required ReaderViewSettings settings,
  required Future<void> Function() onNavigate,
  ValueChanged<String>? onChapterSelected,
  List<ReaderChapter>? chapters,
}) {
  final allChapters = chapters ?? detail.chapters;
  // 预构建扁平化数据（包含 level 和父子关系信息）
  final entries = _buildEntries(allChapters);

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (_) => _ChapterSheet(
          entries: entries,
          currentChapterId: currentChapterId,
          itemId: itemId,
          settings: settings,
          onNavigate: onNavigate,
          onChapterSelected: onChapterSelected,
          readerContext: context,
        ),
  );
}

// ── 数据模型 ──────────────────────────────────────────────────

class _ChapterEntry {
  const _ChapterEntry({
    required this.chapter,
    required this.level,
    required this.isParent,
    required this.childIds,
  });

  final ReaderChapter chapter;
  final int level;
  final bool isParent;
  final List<String> childIds;
}

/// 预构建条目列表，计算父子关系。
List<_ChapterEntry> _buildEntries(List<ReaderChapter> chapters) {
  final entries = <_ChapterEntry>[];
  for (var i = 0; i < chapters.length; i++) {
    final ch = chapters[i];
    // 收集子章节 ID（连续的 level > 当前 level 的章节）
    final childIds = <String>[];
    for (var j = i + 1; j < chapters.length; j++) {
      if (chapters[j].level <= ch.level) break;
      childIds.add(chapters[j].id);
    }
    entries.add(
      _ChapterEntry(
        chapter: ch,
        level: ch.level,
        isParent: childIds.isNotEmpty,
        childIds: childIds,
      ),
    );
  }
  return entries;
}

// ── 弹窗主体 ──────────────────────────────────────────────────

class _ChapterSheet extends StatefulWidget {
  const _ChapterSheet({
    required this.entries,
    required this.currentChapterId,
    required this.itemId,
    required this.settings,
    required this.onNavigate,
    required this.readerContext,
    this.onChapterSelected,
  });

  final List<_ChapterEntry> entries;
  final String currentChapterId;
  final String itemId;
  final ReaderViewSettings settings;
  final Future<void> Function() onNavigate;
  final ValueChanged<String>? onChapterSelected;
  final BuildContext readerContext;

  @override
  State<_ChapterSheet> createState() => _ChapterSheetState();
}

class _ChapterSheetState extends State<_ChapterSheet> {
  final Set<String> _collapsed = {};

  bool _isVisible(_ChapterEntry entry) {
    // level 0 始终可见
    if (entry.level == 0) return true;
    // 向前查找直接父级，判断父级是否折叠
    final idx = widget.entries.indexOf(entry);
    for (var i = idx - 1; i >= 0; i--) {
      final parent = widget.entries[i];
      if (parent.level < entry.level) {
        // 找到直接父级
        return !_collapsed.contains(parent.chapter.id);
      }
    }
    return true;
  }

  void _toggle(String id) {
    setState(() {
      if (_collapsed.contains(id)) {
        _collapsed.remove(id);
      } else {
        _collapsed.add(id);
      }
    });
  }

  Future<void> _onTap(_ChapterEntry entry) async {
    if (entry.isParent) {
      _toggle(entry.chapter.id);
    } else {
      Navigator.pop(context);
      if (entry.chapter.id != widget.currentChapterId) {
        await widget.onNavigate();
        if (widget.onChapterSelected != null) {
          widget.onChapterSelected!(entry.chapter.id);
        } else if (widget.readerContext.mounted) {
          widget.readerContext.pushReplacement(
            '/reader/items/${widget.itemId}/chapters/${entry.chapter.id}',
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.entries.where(_isVisible).toList();
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.7;
    final bottomPadding = mediaQuery.padding.bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: widget.settings.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 拖拽手柄 ──
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: widget.settings.onSurfaceVariantColor.withValues(
                  alpha: 0.25,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // ── 标题栏 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Text(
                  AppLocalizations.of(context).readerChapterList,
                  style: TextStyle(
                    color: widget.settings.onSurfaceColor,
                    fontSize: AppTypography.titleMedium,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.entries.length}',
                  style: TextStyle(
                    color: widget.settings.onSurfaceVariantColor,
                    fontSize: AppTypography.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: widget.settings.onSurfaceVariantColor.withValues(
              alpha: 0.12,
            ),
          ),
          // ── 章节列表 ──
          Flexible(
            child: ListView.builder(
              padding: EdgeInsets.only(bottom: bottomPadding + 8),
              itemCount: visible.length,
              itemBuilder: (_, index) {
                final entry = visible[index];
                final ch = entry.chapter;
                final isCurrent = ch.id == widget.currentChapterId;
                final isExpanded = !_collapsed.contains(ch.id);
                final indent = entry.level * 24.0;

                return InkWell(
                  onTap: () => _onTap(entry),
                  child: Padding(
                    padding: EdgeInsets.only(left: 16 + indent, right: 8),
                    child: SizedBox(
                      height: entry.isParent ? 52 : 48,
                      child: Row(
                        children: [
                          // 当前章节指示
                          if (isCurrent)
                            Container(
                              width: 3,
                              height: 20,
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                color: widget.settings.accentColor,
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                            )
                          else if (entry.level > 0)
                            const SizedBox(width: 15),
                          // 标题
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ch.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        isCurrent
                                            ? widget.settings.accentColor
                                            : widget.settings.onSurfaceColor,
                                    fontSize: entry.level == 0 ? 15 : 14,
                                    fontWeight:
                                        entry.level == 0
                                            ? FontWeight.w600
                                            : isCurrent
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                  ),
                                ),
                                if (entry.level > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      readerChapterLabelText(
                                        AppLocalizations.of(context),
                                        ch.chapterNumber,
                                      ),
                                      style: TextStyle(
                                        color:
                                            widget
                                                .settings
                                                .onSurfaceVariantColor,
                                        fontSize: AppTypography.labelSmall,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // 展开/折叠箭头
                          if (entry.isParent)
                            AnimatedRotation(
                              turns: isExpanded ? 0.25 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: widget.settings.onSurfaceVariantColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
