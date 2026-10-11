import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/domain/reader_chapter_hierarchy.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/reader_l10n_helpers.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 章节列表面板（直接渲染在 Stack 内，不依赖独立路由）。
class ChapterPanel extends StatefulWidget {
  const ChapterPanel({
    required this.chapters,
    required this.currentChapterId,
    required this.settings,
    required this.onChapterTap,
    required this.onDismiss,
    this.embedded = false,
    this.bookTitle,
    super.key,
  });

  final List<ReaderChapter> chapters;
  final String currentChapterId;
  final ReaderViewSettings settings;
  final ValueChanged<String> onChapterTap;
  final VoidCallback onDismiss;
  final bool embedded;

  /// 稿子 `.sheet-header small` 的书名眉标；调用方没有书名时留空不占行。
  final String? bookTitle;

  @override
  State<ChapterPanel> createState() => ChapterPanelState();
}

class ChapterPanelState extends State<ChapterPanel>
    with SingleTickerProviderStateMixin {
  final Set<String> _collapsed = {};
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

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
    final mq = MediaQuery.of(context);
    final chapterList = _buildChapterList(visible, mq);
    final currentIndex = widget.chapters.indexWhere(
      (chapter) => chapter.id == widget.currentChapterId,
    );

    if (widget.embedded) {
      return chapterList;
    }

    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        decoration: BoxDecoration(
          // 稿子 `.bottom-sheet`：--glass-solid 实底、顶部 r28、三边 --line 描边
          //（底边贴屏幕不画）、投影 0 -20 60。
          color: widget.settings.glassSolidColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: widget.settings.lineColor),
            left: BorderSide(color: widget.settings.lineColor),
            right: BorderSide(color: widget.settings.lineColor),
          ),
          boxShadow: [
            BoxShadow(
              color: widget.settings.shadowColor,
              blurRadius: 60,
              offset: const Offset(0, -20),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽手柄：稿子 .sheet-handle 38×4 r3，正文墨色 18%。
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: widget.settings.onSurfaceColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            // 标题栏：9/700 强调色书名 + 25/600 衬线面板名。
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((widget.bookTitle ?? '').isNotEmpty)
                          Text(
                            widget.bookTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.settings.accentColor,
                              fontSize: AppTypography.labelNano,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.08,
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            AppLocalizations.of(context).readerChapterList,
                            style: TextStyle(
                              fontFamily: AppTypography.serifFamily,
                              fontFamilyFallback:
                                  AppTypography.serifFamilyFallback,
                              color: widget.settings.onSurfaceColor,
                              fontSize: 25, // ignore: font_size_whitelist
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onDismiss,
                    tooltip: AppLocalizations.of(context).readerClose,
                    iconSize: 20,
                    color: widget.settings.onSurfaceVariantColor,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            // .chapter-summary：左右两段 10px 弱化信息，底下压一条发丝线。
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      currentIndex < 0
                          ? AppLocalizations.of(context).readerChapterList
                          : widget.chapters[currentIndex].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.settings.onSurfaceVariantColor,
                        fontSize: AppTypography.labelMicro,
                      ),
                    ),
                  ),
                  Text(
                    '${currentIndex + 1} / ${widget.chapters.length}',
                    style: TextStyle(
                      color: widget.settings.onSurfaceVariantColor,
                      fontSize: AppTypography.labelMicro,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: widget.settings.lineColor),
            // 章节列表（Expanded 确保占满剩余空间）
            Expanded(child: chapterList),
          ],
        ),
      ),
    );
  }

  Widget _buildChapterList(
    List<ReaderChapter> visible,
    MediaQueryData mediaQuery,
  ) {
    return ListView.builder(
      padding: EdgeInsets.only(bottom: mediaQuery.padding.bottom + 8),
      itemCount: visible.length,
      itemBuilder: (_, index) {
        final chapter = visible[index];
        final isCurrent = chapter.id == widget.currentChapterId;
        final isParent = _hasChildren(chapter);
        final isExpanded = !_collapsed.contains(chapter.id);
        final indent = chapter.level * 24.0;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              // 父章节也可直接跳转（部标题可能自带正文）；展开交给尾部 chevron。
              widget.onChapterTap(chapter.id);
            },
            child: Padding(
              padding: EdgeInsets.only(left: 12 + indent, right: 8),
              child: Container(
                // 稿子 `.chapter-list button`：min-height 65、padding 8 4、
                // gap 12，每行底下一条 --line 发丝线。
                constraints: const BoxConstraints(minHeight: 65),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: widget.settings.lineColor),
                  ),
                ),
                child: Row(
                  children: [
                    // .chapter-number：27 宽衬线序号；当前章整行转强调色。
                    SizedBox(
                      width: 27,
                      child:
                          chapter.level > 0
                              ? Icon(
                                Icons.circle,
                                color: widget.settings.faintColor,
                                size: 5,
                              )
                              : Text(
                                '${index + 1}',
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
                    const SizedBox(width: 12),
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
                              color:
                                  isCurrent
                                      ? widget.settings.accentColor
                                      : widget.settings.onSurfaceColor,
                              fontSize: chapter.level == 0 ? 15 : 14,
                              fontWeight:
                                  chapter.level == 0
                                      ? FontWeight.w600
                                      : isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                            ),
                          ),
                          if (chapter.level > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                readerChapterLabelText(
                                  AppLocalizations.of(context),
                                  chapter.chapterNumber,
                                ),
                                style: TextStyle(
                                  color: widget.settings.onSurfaceVariantColor,
                                  fontSize: AppTypography.labelSmall,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
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
}
