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
    super.key,
  });

  final List<ReaderChapter> chapters;
  final String currentChapterId;
  final ReaderViewSettings settings;
  final ValueChanged<String> onChapterTap;
  final VoidCallback onDismiss;
  final bool embedded;

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
          color: widget.settings.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽手柄
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
            // 标题栏
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
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: widget.settings.onSurfaceVariantColor,
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
              padding: EdgeInsets.only(left: 16 + indent, right: 8),
              child: SizedBox(
                height: isParent ? 52 : 48,
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child:
                          isCurrent
                              ? Icon(
                                Icons.play_arrow_rounded,
                                color: widget.settings.accentColor,
                                size: 18,
                              )
                              : chapter.level > 0
                              ? Icon(
                                Icons.circle,
                                color: widget.settings.onSurfaceVariantColor
                                    .withValues(alpha: 0.35),
                                size: 5,
                              )
                              : null,
                    ),
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
