import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/domain/reader_chapter_hierarchy.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/reader_l10n_helpers.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

// 稿子 `.chapter-*` 的签名密度：12/9/10 三档靠色阶分层，不随字号设置放大，
// 也不为了"更好读"整体上抬（见 living-glass 红线 4）。
const double _rowMinHeight = 65;
const double _rowVerticalPadding = 8;
const double _rowHorizontalPadding = 4;
const double _rowGap = 12;
const double _listHorizontalPadding = 20;
const double _numberWidth = 27;
const double _titleFontSize = AppTypography.bodySmall;
const double _subLabelFontSize = AppTypography.labelNano;
const double _subLabelTopGap = 4;
const double _pillFontSize = 8;
const double _pillMinHeight = 24;
const double _summaryFontSize = AppTypography.labelMicro;
const double _summaryTextGap = 14;
const double _summaryListGap = 8;

/// 卷/节层级的缩进。稿子是平铺列表，层级是本书 TOC 带进来的数据结构。
const double _levelIndent = 24;

/// 章节列表：稿子 `.chapter-summary` + `.chapter-list`。
///
/// 抽屉外壳（手柄、眉标、面板名、关闭钮、遮罩）由 `ReaderAdaptivePanelFrame`
/// 统一绘制，本组件只交列表本体。
class ChapterPanel extends StatefulWidget {
  const ChapterPanel({
    required this.chapters,
    required this.currentChapterId,
    required this.settings,
    required this.onChapterTap,
    super.key,
  });

  final List<ReaderChapter> chapters;
  final String currentChapterId;
  final ReaderViewSettings settings;
  final ValueChanged<String> onChapterTap;

  @override
  State<ChapterPanel> createState() => ChapterPanelState();
}

class ChapterPanelState extends State<ChapterPanel> {
  final Set<String> _collapsed = {};

  bool _hasChildren(ReaderChapter chapter) {
    return ReaderChapterHierarchy.hasChildren(widget.chapters, chapter);
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

  @override
  Widget build(BuildContext context) {
    final visible = ReaderChapterHierarchy.visibleChapters(
      widget.chapters,
      _collapsed,
    );
    final currentIndex = widget.chapters.indexWhere(
      (chapter) => chapter.id == widget.currentChapterId,
    );

    return Column(
      children: [
        _buildSummary(context, currentIndex),
        Expanded(child: _buildChapterList(visible)),
      ],
    );
  }

  /// `.chapter-summary`：左右两段 10px 弱化信息，底下压一条发丝线。
  Widget _buildSummary(BuildContext context, int currentIndex) {
    final l10n = AppLocalizations.of(context);
    final summaryStyle = TextStyle(
      color: widget.settings.onSurfaceVariantColor,
      fontSize: _summaryFontSize,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, _summaryListGap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: _summaryTextGap),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.readerTotalChapters('${widget.chapters.length}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: summaryStyle,
                  ),
                ),
                if (currentIndex >= 0)
                  Text(
                    l10n.readerChapterPosition(
                      currentIndex + 1,
                      widget.chapters.length,
                    ),
                    style: summaryStyle,
                  ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: widget.settings.lineColor),
        ],
      ),
    );
  }

  Widget _buildChapterList(List<ReaderChapter> visible) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        _listHorizontalPadding,
        0,
        _listHorizontalPadding,
        bottomInset + 8,
      ),
      itemCount: visible.length,
      itemBuilder: (_, index) {
        final chapter = visible[index];
        final isCurrent = chapter.id == widget.currentChapterId;
        final isParent = _hasChildren(chapter);
        final isExpanded = !_collapsed.contains(chapter.id);
        final indent = chapter.level * _levelIndent;
        // 当前行转强调色是整行的事（稿子 `.chapter-list button.current`），
        // 副标题另有显式 --muted，不跟着变。
        final rowColor =
            isCurrent
                ? widget.settings.accentColor
                : widget.settings.onSurfaceColor;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              // 父章节也可直接跳转（部标题可能自带正文）；展开交给尾部 chevron。
              widget.onChapterTap(chapter.id);
            },
            child: Padding(
              padding: EdgeInsets.only(left: indent),
              child: Container(
                constraints: const BoxConstraints(minHeight: _rowMinHeight),
                padding: const EdgeInsets.symmetric(
                  horizontal: _rowHorizontalPadding,
                  vertical: _rowVerticalPadding,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: widget.settings.lineColor),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: _numberWidth,
                      child:
                          chapter.level > 0
                              ? Icon(
                                Icons.circle,
                                color: widget.settings.faintColor,
                                size: 5,
                              )
                              : Text(
                                // 稿子 String(index + 1).padStart(2, '0')
                                '${index + 1}'.padLeft(2, '0'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: AppTypography.serifFamily,
                                  fontFamilyFallback:
                                      AppTypography.serifFamilyFallback,
                                  fontSize: AppTypography.titleSmall,
                                  color:
                                      isCurrent
                                          ? widget.settings.accentColor
                                          : widget.settings.faintColor,
                                ),
                              ),
                    ),
                    const SizedBox(width: _rowGap),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chapter.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: rowColor,
                              fontSize: _titleFontSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (chapter.level > 0)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: _subLabelTopGap,
                              ),
                              child: Text(
                                readerChapterLabelText(
                                  AppLocalizations.of(context),
                                  chapter.chapterNumber,
                                ),
                                style: TextStyle(
                                  color: widget.settings.onSurfaceVariantColor,
                                  fontSize: _subLabelFontSize,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: _rowGap),
                      _buildReadingPill(context),
                    ],
                    if (isParent)
                      IconButton(
                        onPressed: () => _toggle(chapter.id),
                        tooltip:
                            isExpanded
                                ? AppLocalizations.of(context).readerCollapse
                                : AppLocalizations.of(context).readerExpand,
                        visualDensity: VisualDensity.compact,
                        icon: AnimatedRotation(
                          turns: isExpanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: widget.settings.onSurfaceVariantColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// `.reading-pill`：min-height 24、padding 0 8、r8、--accent-soft 底、8px 字。
  Widget _buildReadingPill(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: _pillMinHeight),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: widget.settings.accentSoftColor,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        AppLocalizations.of(context).readerNowReading,
        style: TextStyle(
          color: widget.settings.accentColor,
          fontSize: _pillFontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
