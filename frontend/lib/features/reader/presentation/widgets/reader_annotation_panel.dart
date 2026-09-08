import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_annotation_handler.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 阅读批注列表面板（底部弹出）。
///
/// 支持按关键词搜索批注，以及切换「本章」/「全书」范围。
class ReaderAnnotationPanel extends StatefulWidget {
  const ReaderAnnotationPanel({
    required this.annotations,
    required this.allAnnotations,
    required this.chapters,
    required this.settings,
    this.onDelete,
    this.onEdit,
    this.embedded = false,
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
  final bool embedded;

  @override
  State<ReaderAnnotationPanel> createState() => _ReaderAnnotationPanelState();
}

class _ReaderAnnotationPanelState extends State<ReaderAnnotationPanel> {
  String _searchQuery = '';
  bool _showAllChapters = false;

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
    final textColor = widget.settings.onSurfaceColor;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    final content = Column(
      mainAxisSize: widget.embedded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (!widget.embedded) _buildDragHandle(textColor),
        if (!widget.embedded) _buildHeader(l10n, textColor),
        _buildSearchBar(l10n, textColor),
        _buildChapterToggle(l10n, textColor),
        if (widget.embedded)
          Expanded(child: _buildBody(l10n, textColor))
        else
          Flexible(child: _buildBody(l10n, textColor)),
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: widget.settings.surfaceColor.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: widget.settings.onSurfaceColor.withValues(alpha: 0.10),
          ),
        ),
      ),
      child: content,
    );
  }

  Widget _buildDragHandle(Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: textColor.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n, Color textColor) {
    final filtered = _filteredAnnotations;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          Icon(Icons.edit_note_rounded, color: textColor, size: 20),
          const SizedBox(width: 10),
          Text(
            '${l10n.readerAnnotations}（${filtered.length}）',
            style: TextStyle(
              color: textColor,
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索输入框。
  Widget _buildSearchBar(AppLocalizations l10n, Color textColor) {
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
          fillColor: widget.settings.onSurfaceColor.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: widget.settings.onSurfaceColor.withValues(alpha: 0.08),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: widget.settings.onSurfaceColor.withValues(alpha: 0.08),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: widget.settings.onSurfaceColor.withValues(alpha: 0.20),
            ),
          ),
        ),
      ),
    );
  }

  /// 「本章」/「全书」切换按钮。
  Widget _buildChapterToggle(AppLocalizations l10n, Color textColor) {
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
                ? widget.settings.surfaceColor
                : textColor;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? widget.settings.accentColor
                : widget.settings.onSurfaceColor.withValues(alpha: 0.06);
          }),
          side: WidgetStatePropertyAll(
            BorderSide(
              color: widget.settings.onSurfaceVariantColor.withValues(
                alpha: 0.24,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, Color textColor) {
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
          chapterTitle: chapterName,
          onDelete: widget.onDelete,
          onEdit: widget.onEdit,
        );
      },
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, Color textColor) {
    return Padding(
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
    this.chapterTitle,
    this.onDelete,
    this.onEdit,
  });

  final ReaderAnnotation annotation;
  final ReaderViewSettings settings;

  /// 全书模式下显示的章节标题，为空则不展示。
  final String? chapterTitle;

  final ValueChanged<ReaderAnnotation>? onDelete;
  final ValueChanged<ReaderAnnotation>? onEdit;

  bool get _hasNote => annotation.note?.trim().isNotEmpty == true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final highlightColor = ReaderAnnotationHandler.parseAnnotationColor(
      annotation.color,
    );
    final textColor = settings.onSurfaceColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: settings.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: settings.onSurfaceVariantColor.withValues(alpha: 0.20),
          ),
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
        if (_hasNote && onEdit != null)
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
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: textColor.withValues(alpha: 0.55)),
        ),
      ),
    );
  }
}
