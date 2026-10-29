import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/reader/application/reader_data_manager.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_annotation_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 阅读器批注操作辅助类。
///
/// 封装批注的加载、创建、编辑、删除和面板展示逻辑，
/// 从 reader_view_page.dart 中提取以控制文件行数。
/// 所有写操作通过 ReaderDataManager 实现离线优先。
class ReaderAnnotationHandler {
  ReaderAnnotationHandler({
    required this.itemId,
    required this.chapterId,
    required this.dataManager,
    required this.settings,
    required this.onAnnotationsChanged,
    this.onSelectAnnotation,
    this.chapters = const [],
  });

  final String itemId;
  String chapterId;
  final ReaderDataManager dataManager;
  ReaderViewSettings settings;
  final VoidCallback onAnnotationsChanged;

  /// 点按批注卡片时请求跳转到该批注的章节与章内偏移。
  final void Function(String? chapterId, int startOffset)? onSelectAnnotation;

  /// 章节列表，用于在全书批注模式下查找章节标题。
  List<ReaderChapter> chapters;

  List<ReaderAnnotation> _annotations = [];

  // 章节批注过滤结果缓存：以 _annotations 列表身份 + 章节为键。
  // 批注重载（新列表身份）或切章自然失效，调用方在整页重建时
  // 拿到稳定身份，下游 identical 判定生效、避免全章重投影。
  List<ReaderAnnotation>? _chapterFilterCache;
  List<ReaderAnnotation>? _chapterFilterSource;
  String? _chapterFilterId;

  List<ReaderAnnotation> get annotations => _annotations;

  List<ReaderAnnotation> get chapterAnnotations =>
      annotationsForChapter(chapterId);

  /// 指定章节的批注。
  List<ReaderAnnotation> annotationsForChapter(String id) {
    if (_chapterFilterSource == null ||
        !identical(_chapterFilterSource, _annotations) ||
        _chapterFilterId != id) {
      _chapterFilterSource = _annotations;
      _chapterFilterId = id;
      _chapterFilterCache =
          _annotations.where((a) => a.chapterId == id).toList();
    }
    return _chapterFilterCache!;
  }

  /// 更新当前章节，确保批注读写使用正在显示的章节。
  void updateChapter(String value) {
    chapterId = value;
  }

  /// 更新阅读设置，确保批注面板沿用当前主题。
  void updateSettings(ReaderViewSettings value) {
    settings = value;
  }

  /// 加载所有批注。
  Future<void> load() async {
    try {
      _annotations = await dataManager.loadAnnotations(itemId);
      onAnnotationsChanged();
    } on Exception catch (e) {
      if (kDebugMode) {
        readerDebugLog('ReaderAnnotationHandler: annotation load failed: $e');
      }
    }
  }

  /// 删除与指定范围重叠的已有批注（用于替换高亮/批注）。
  ///
  /// chapterId 由调用方在入口原子捕获：await 窗口内连续滚动的锚点
  /// 收养会改写字段，旧章偏移的删除/写入不得漂移到新章。
  Future<void> _deleteOverlapping(
    String chapterId,
    int startOffset,
    int endOffset,
  ) async {
    final overlapping =
        _annotations
            .where(
              (a) =>
                  a.chapterId == chapterId &&
                  a.startOffset < endOffset &&
                  a.endOffset > startOffset,
            )
            .toList();
    for (final a in overlapping) {
      try {
        await dataManager.deleteAnnotation(a.id);
      } on Exception catch (e) {
        if (kDebugMode) {
          readerDebugLog(
            'ReaderAnnotationHandler: overlapping delete failed: $e',
          );
        }
        // 删除失败上抛：替换语义下旧批注未清除不能继续写入新批注。
        rethrow;
      }
    }
  }

  /// 创建高亮（无备注），替换范围内已有的高亮/批注。
  Future<void> highlight(
    String selectedText,
    int startOffset,
    int endOffset,
    BuildContext context,
  ) async {
    final chapter = chapterId;
    try {
      await _deleteOverlapping(chapter, startOffset, endOffset);
      await dataManager.createAnnotation(
        itemId: itemId,
        chapterId: chapter,
        startOffset: startOffset,
        endOffset: endOffset,
        highlightText: selectedText,
        color: '#FFEB3B',
      );
      await load();
      if (context.mounted) {
        showReaderSnackBar(
          context,
          AppLocalizations.of(context).readerHighlightAdded,
        );
      }
    } on Exception catch (e) {
      // 高亮是用户显式动作，失败必须可感知，否则用户误以为已保存。
      if (kDebugMode) {
        readerDebugLog(
          'ReaderAnnotationHandler: highlight creation failed: $e',
        );
      }
      if (context.mounted) {
        showReaderSnackBar(
          context,
          AppLocalizations.of(context).readerAnnotationSaveFailed,
        );
      }
    }
  }

  /// 预设批注颜色列表。
  static const List<String> _presetColors = [
    '#FFEB3B', // 黄色（高亮默认）
    '#4CAF50', // 绿色
    '#2196F3', // 蓝色
    '#E91E63', // 粉色
    '#E0E0E0', // 浅灰色（批注默认，亮暗主题均可见）
  ];

  /// 将批注颜色字符串解析为 Color，无效值回退为黄色。
  ///
  /// 供 [ReaderViewContent] 等外部组件调用以避免重复实现。
  static Color parseAnnotationColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return Colors.yellow;
    try {
      final hex = colorStr.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.yellow;
    }
  }

  /// 批注存色可能为空或不在预设内；编辑对话框只能选中预设格，回落批注默认色。
  static String _presetColorOrDefault(String? color) =>
      _presetColors.contains(color) ? color! : '#E0E0E0';

  /// 创建批注（弹出输入弹窗）。
  Future<void> annotate(
    String selectedText,
    int startOffset,
    int endOffset,
    BuildContext context,
  ) async {
    // 弹窗 await 窗口长，章节归属必须在此刻原子捕获。
    final chapter = chapterId;
    final l10n = AppLocalizations.of(context);

    final result = await showWorkstationDialog<_AnnotationDraft>(
      context: context,
      builder:
          (_) => _AnnotationDialog(
            title: l10n.readerAddAnnotation,
            quote: selectedText,
            initialColor: '#E0E0E0',
            requireNote: true,
          ),
    );

    if (result != null) {
      try {
        await _deleteOverlapping(chapter, startOffset, endOffset);
        await dataManager.createAnnotation(
          itemId: itemId,
          chapterId: chapter,
          startOffset: startOffset,
          endOffset: endOffset,
          highlightText: selectedText,
          note: result.note,
          color: result.color,
        );
        await load();
      } on Exception catch (e) {
        // 批注是用户显式动作，失败必须可感知，否则用户误以为已保存。
        if (kDebugMode) {
          readerDebugLog(
            'ReaderAnnotationHandler: annotation creation failed: $e',
          );
        }
        if (context.mounted) {
          showReaderSnackBar(
            context,
            AppLocalizations.of(context).readerAnnotationSaveFailed,
          );
        }
      }
    }
  }

  /// 删除批注。
  Future<void> delete(ReaderAnnotation annotation, BuildContext context) async {
    try {
      await dataManager.deleteAnnotation(annotation.id);
      await load();
    } on Exception catch (e) {
      // 与新增/编辑同口径：删除失败必须可感知，否则批注原地留着，
      // 用户以为已经删掉，下次进来还在。
      if (kDebugMode) {
        readerDebugLog('ReaderAnnotationHandler: annotation delete failed: $e');
      }
      if (context.mounted) {
        showReaderSnackBar(
          context,
          AppLocalizations.of(context).readerAnnotationDeleteFailed,
        );
      }
    }
  }

  /// 编辑批注的备注与高亮色；把备注清空即等于取消附注，保留高亮。
  Future<void> edit(ReaderAnnotation annotation, BuildContext context) async {
    final l10n = AppLocalizations.of(context);

    final result = await showWorkstationDialog<_AnnotationDraft>(
      context: context,
      builder:
          (_) => _AnnotationDialog(
            title: l10n.readerEditAnnotation,
            initialNote: annotation.note,
            initialColor: _presetColorOrDefault(annotation.color),
          ),
    );

    if (result != null) {
      try {
        await dataManager.updateAnnotation(
          annotationId: annotation.id,
          note: result.note,
          color: result.color,
        );
        await load();
      } on Exception catch (e) {
        // 编辑是用户显式动作，失败必须可感知，否则用户以为清空已生效。
        if (kDebugMode) {
          readerDebugLog('ReaderAnnotationHandler: annotation edit failed: $e');
        }
        if (context.mounted) {
          showReaderSnackBar(
            context,
            AppLocalizations.of(context).readerAnnotationSaveFailed,
          );
        }
      }
    }
  }

  /// 构建由阅读器自适应面板承载的批注内容。
  Widget buildPanel(BuildContext context) {
    return ReaderAnnotationPanel(
      annotations: chapterAnnotations,
      allAnnotations: _annotations,
      chapters: chapters,
      settings: settings,
      onDelete: (annotation) async {
        await delete(annotation, context);
      },
      onEdit: (annotation) {
        edit(annotation, context);
      },
      onSelect:
          onSelectAnnotation == null
              ? null
              : (annotation) => onSelectAnnotation!(
                annotation.chapterId,
                annotation.startOffset,
              ),
    );
  }
}

/// 预设高亮色选一列：新建与编辑批注对话框共用同一份色板与选中态。
class _PresetColorRow extends StatelessWidget {
  const _PresetColorRow({required this.selectedColor, required this.onChanged});

  final String selectedColor;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final colorHex in ReaderAnnotationHandler._presetColors)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () => onChanged(colorHex),
              customBorder: const CircleBorder(),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ReaderAnnotationHandler.parseAnnotationColor(colorHex),
                  border: Border.all(
                    color:
                        selectedColor == colorHex
                            ? Theme.of(context).colorScheme.outline
                            : Colors.transparent,
                    width: 2,
                  ),
                ),
                child:
                    selectedColor == colorHex
                        ? const Icon(Icons.check, size: 16, color: Colors.black)
                        : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// 批注对话框的确认结果。
class _AnnotationDraft {
  const _AnnotationDraft({required this.note, required this.color});

  final String note;
  final String color;
}

/// 批注编辑对话框：新建与修改共用。
///
/// 文本控制器与色板选中态由对话框自身释放。调用方若在弹层退场动画期间
/// 继续 await 后 dispose 控制器，TextField 会在已销毁的控制器上重新
/// addListener，触发 `A TextEditingController was used after being disposed`。
class _AnnotationDialog extends StatefulWidget {
  const _AnnotationDialog({
    required this.title,
    required this.initialColor,
    this.initialNote,
    this.quote,
    this.requireNote = false,
  });

  final String title;
  final String initialColor;
  final String? initialNote;

  /// 新建时展示的引文；修改时为 null。
  final String? quote;

  /// 新建必须写备注；修改允许清空备注。
  final bool requireNote;

  @override
  State<_AnnotationDialog> createState() => _AnnotationDialogState();
}

class _AnnotationDialogState extends State<_AnnotationDialog> {
  late final TextEditingController _noteController = TextEditingController(
    text: widget.initialNote,
  );
  late String _selectedColor = widget.initialColor;
  late bool _noteEmpty = _noteController.text.trim().isEmpty;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      // 键盘弹出时引文+备注+色板可能超出可用高，滚动兜底。
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.quote != null) ...[
              _QuoteBox(text: widget.quote!),
              const SizedBox(height: 12),
            ],
            _PresetColorRow(
              selectedColor: _selectedColor,
              onChanged:
                  (colorHex) => setState(() => _selectedColor = colorHex),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 3,
              onChanged: (value) {
                setState(() => _noteEmpty = value.trim().isEmpty);
              },
              decoration: InputDecoration(
                hintText: l10n.readerAnnotationHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed:
              _noteEmpty && widget.requireNote
                  ? null
                  : () => Navigator.pop(
                    context,
                    _AnnotationDraft(
                      note: _noteController.text.trim(),
                      color: _selectedColor,
                    ),
                  ),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

/// 新建批注时展示的选中文本引用块。
class _QuoteBox extends StatelessWidget {
  const _QuoteBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 150),
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: AppTypography.bodyMedium,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }
}
