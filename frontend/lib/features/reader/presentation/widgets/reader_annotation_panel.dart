import 'package:material_ui/material_ui.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_annotation_handler.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 批注卡片上的编辑/删除钮触控边长。稿子没有批注抽屉，取本项目次级控件下限 35。
const double _actionTargetSize = 35;

/// 阅读批注列表：由阅读器自适应面板承载，不再自带底部抽屉。
///
/// 支持按关键词搜索批注，以及切换「本章」/「全书」范围。
class ReaderAnnotationPanel extends StatefulWidget {
  const ReaderAnnotationPanel({
    required this.annotations,
    required this.allAnnotations,
    required this.chapters,
    required this.settings,
    this.bookmarks = const [],
    this.onSelectBookmark,
    this.onDeleteBookmark,
    this.onDelete,
    this.onEdit,
    this.onSelect,
    super.key,
  });

  /// 当前章节的批注列表。
  final List<ReaderAnnotation> annotations;

  /// 所有章节的批注列表（用于全书模式）。
  final List<ReaderAnnotation> allAnnotations;

  /// 章节列表，用于在全书模式下查找章节标题。
  final List<ReaderChapter> chapters;

  final ReaderViewSettings settings;
  final ValueChanged<ReaderAnnotation>? onDelete;
  final ValueChanged<ReaderAnnotation>? onEdit;

  /// 点按卡片时回调：跳转到批注所在章节与偏移。
  final ValueChanged<ReaderAnnotation>? onSelect;
  final List<ReaderBookmark> bookmarks;
  final ValueChanged<ReaderBookmark>? onSelectBookmark;
  final ValueChanged<ReaderBookmark>? onDeleteBookmark;

  @override
  State<ReaderAnnotationPanel> createState() => _ReaderAnnotationPanelState();
}

class _ReaderAnnotationPanelState extends State<ReaderAnnotationPanel> {
  String _searchQuery = '';
  bool _showAllChapters = false;
  bool _showBookmarksTab = false;

  /// 根据当前范围和搜索关键词过滤批注。
  List<ReaderAnnotation> get _filteredAnnotations {
    final source =
        _showAllChapters ? widget.allAnnotations : widget.annotations;
    if (_searchQuery.trim().isEmpty) {
      return source;
    }
    final query = _searchQuery.toLowerCase();
    return source.where((a) {
      final highlight = a.highlightText?.toLowerCase() ?? '';
      final note = a.note?.toLowerCase() ?? '';
      return highlight.contains(query) || note.contains(query);
    }).toList();
  }

  /// 根据 chapterId 查找章节标题。
  String _chapterTitle(String? chapterId) {
    if (chapterId == null) return '';
    final match = widget.chapters.where((c) => c.id == chapterId);
    return match.isNotEmpty ? match.first.title : '';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ReaderPanelColors.resolve(context, widget.settings.palette);
    final textColor = colors.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: _PanelTabButton(
                  label:
                      '${l10n.readerAnnotations} (${widget.allAnnotations.length})',
                  selected: !_showBookmarksTab,
                  colors: colors,
                  onTap: () => setState(() => _showBookmarksTab = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PanelTabButton(
                  label: l10n.readerBookmarksTab(widget.bookmarks.length),
                  selected: _showBookmarksTab,
                  colors: colors,
                  onTap: () => setState(() => _showBookmarksTab = true),
                ),
              ),
            ],
          ),
        ),
        if (_showBookmarksTab)
          Expanded(child: _buildBookmarksList(colors))
        else ...[
          _buildSummary(l10n, colors),
          _buildSearchBar(l10n, colors),
          _buildChapterToggle(l10n, colors),
          Expanded(child: _buildBody(l10n, textColor, colors)),
        ],
      ],
    );
  }

  Widget _buildBookmarksList(ReaderPanelColors colors) {
    final l10n = AppLocalizations.of(context);
    if (widget.bookmarks.isEmpty) {
      return Center(
        child: Text(
          l10n.readerNoBookmarks,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: AppTypography.bodyMedium,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: widget.bookmarks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final bm = widget.bookmarks[index];
        final title = _chapterTitle(bm.chapterId);
        final pct = (bm.progressPercent * 100).round();
        return Material(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: () => widget.onSelectBookmark?.call(bm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.bookmark_rounded, size: 16, color: colors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.isNotEmpty
                              ? title
                              : l10n.readerBookmarkFallback(index + 1),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: AppTypography.bodyMedium,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '$pct%',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: AppTypography.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onDeleteBookmark != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                      onPressed: () => widget.onDeleteBookmark?.call(bm),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 批注计数行：撤下私有标题栏后保留「有多少条」这一信息。
  Widget _buildSummary(AppLocalizations l10n, ReaderPanelColors colors) {
    final filtered = _filteredAnnotations;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        l10n.readerAnnotationCount(filtered.length),
        style: TextStyle(
          color: colors.onSurfaceVariant,
          fontSize: AppTypography.labelMicro,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  /// 搜索输入框。
  Widget _buildSearchBar(AppLocalizations l10n, ReaderPanelColors colors) {
    final textColor = colors.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        style: TextStyle(color: textColor, fontSize: AppTypography.bodyLarge),
        decoration: InputDecoration(
          hintText: l10n.readerSearchAnnotationsHint,
          hintStyle: TextStyle(
            color: textColor.withValues(alpha: 0.40),
            fontSize: AppTypography.bodyLarge,
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: textColor.withValues(alpha: 0.45),
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          filled: true,
          fillColor: colors.controlFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colors.accent.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }

  /// 「本章」/「全书」切换按钮。
  Widget _buildChapterToggle(AppLocalizations l10n, ReaderPanelColors colors) {
    final textColor = colors.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment<bool>(
            value: false,
            label: Text(l10n.readerThisChapter),
          ),
          ButtonSegment<bool>(value: true, label: Text(l10n.readerAllChapters)),
        ],
        selected: {_showAllChapters},
        onSelectionChanged: (Set<bool> selected) {
          setState(() => _showAllChapters = selected.first);
        },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: AppTypography.bodyMedium),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? ReaderReadingPalette.onAccentInk
                : textColor;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? colors.accent
                : colors.controlFill;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: colors.line)),
        ),
      ),
    );
  }

  Widget _buildBody(
    AppLocalizations l10n,
    Color textColor,
    ReaderPanelColors colors,
  ) {
    final filtered = _filteredAnnotations;
    if (filtered.isEmpty) {
      return _buildEmptyState(l10n, textColor);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final annotation = filtered[index];
        final chapterName =
            _showAllChapters ? _chapterTitle(annotation.chapterId) : '';
        return _AnnotationCard(
          annotation: annotation,
          settings: widget.settings,
          colors: colors,
          chapterTitle: chapterName,
          onDelete: widget.onDelete,
          onEdit: widget.onEdit,
          onSelect: widget.onSelect,
        );
      },
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, Color textColor) {
    // 窄屏 + 大字号下空态高度可能超过剩余槽位，放进滚动容器避免 RenderFlex 溢出。
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.note_alt_outlined,
            size: 44,
            color: textColor.withValues(alpha: 0.22),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.readerNoAnnotations,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.45),
              fontSize: AppTypography.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单条批注卡片。
class _AnnotationCard extends StatelessWidget {
  const _AnnotationCard({
    required this.annotation,
    required this.settings,
    required this.colors,
    this.chapterTitle,
    this.onDelete,
    this.onEdit,
    this.onSelect,
  });

  final ReaderAnnotation annotation;
  final ReaderViewSettings settings;
  final ReaderPanelColors colors;

  /// 全书模式下显示的章节标题，为空则不展示。
  final String? chapterTitle;

  final ValueChanged<ReaderAnnotation>? onDelete;
  final ValueChanged<ReaderAnnotation>? onEdit;

  /// 点按卡片跳转到批注位置；为 null 时卡片不可点。
  final ValueChanged<ReaderAnnotation>? onSelect;

  bool get _hasNote => annotation.note?.trim().isNotEmpty == true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final highlightColor = ReaderAnnotationHandler.parseAnnotationColor(
      annotation.color,
    );
    final textColor = colors.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // 整卡点按跳批注位置；卡内的编辑/删除钮仍各自独立命中。
          onTap: onSelect == null ? null : () => onSelect!.call(annotation),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (chapterTitle != null && chapterTitle!.isNotEmpty) ...[
                  Text(
                    chapterTitle!,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.50),
                      fontSize: AppTypography.bodySmall,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (_hasNote) ...[
                  Text(
                    annotation.note!,
                    style: TextStyle(
                      color: textColor,
                      fontSize: AppTypography.bodyLarge,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                _buildHighlightedText(highlightColor, textColor),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _buildActions(l10n, textColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedText(Color highlightColor, Color textColor) {
    final bgColor = highlightColor.withValues(alpha: 0.20);
    final borderColor = highlightColor.withValues(alpha: 0.7);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: borderColor, width: 3)),
      ),
      child: Text(
        annotation.highlightText ?? '',
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontSize: AppTypography.bodyMedium,
          height: 1.5,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildActions(AppLocalizations l10n, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onEdit != null)
          _SmallIconButton(
            icon: Icons.edit_outlined,
            tooltip: l10n.readerEditAnnotation,
            textColor: textColor,
            onTap: () => onEdit?.call(annotation),
          ),
        if (onDelete != null)
          _SmallIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: l10n.readerDeleteAnnotation,
            textColor: textColor,
            onTap: () => onDelete?.call(annotation),
          ),
      ],
    );
  }
}

/// 小型图标按钮，用于批注卡片操作。
class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.textColor,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final Color textColor;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: _actionTargetSize,
          height: _actionTargetSize,
          child: Center(
            child: Icon(
              icon,
              size: 18,
              color: textColor.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelTabButton extends StatelessWidget {
  const _PanelTabButton({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final ReaderPanelColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? colors.controlActiveFill : colors.controlFill,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? colors.onSurface : colors.onSurfaceVariant,
              fontSize: AppTypography.bodyMedium,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
