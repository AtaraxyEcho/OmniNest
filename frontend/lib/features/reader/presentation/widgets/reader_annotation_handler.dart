import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/reader/application/reader_data_manager.dart';
import 'package:omninest/features/reader/domain/reader_highlight_palette.dart';
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
  final Map<
    String,
    ({
      ReaderAnnotation annotation,
      int index,
      Timer timer,
      BuildContext context,
    })
  >
  _pendingDeletes = {};

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
      final loaded = await dataManager.loadAnnotations(itemId);
      final pendingIds = _pendingDeletes.keys.toSet();
      _annotations = loaded.where((a) => !pendingIds.contains(a.id)).toList();
      onAnnotationsChanged();
    } on Exception catch (e) {
      if (kDebugMode) {
        readerDebugLog('ReaderAnnotationHandler: annotation load failed: $e');
      }
    }
  }

  /// 查找与指定范围重叠的已有批注（用于替换高亮/批注）。
  ///
  /// chapterId 由调用方在入口原子捕获：await 窗口内连续滚动的锚点
  /// 收养会改写字段，旧章偏移的删除/写入不得漂移到新章。
  List<ReaderAnnotation> _findOverlapping(
    String chapterId,
    int startOffset,
    int endOffset,
  ) {
    return _annotations
        .where(
          (a) =>
              a.chapterId == chapterId &&
              a.startOffset < endOffset &&
              a.endOffset > startOffset,
        )
        .toList();
  }

  /// 合并被覆盖批注的备注，合并高亮时绝不静默抹除用户长笔记。
  String? _mergedNote(
    Iterable<ReaderAnnotation> overlapping, {
    String? primary,
  }) {
    final notes = <String>[
      if (primary != null && primary.trim().isNotEmpty) primary.trim(),
      ...overlapping
          .map((a) => a.note?.trim())
          .whereType<String>()
          .where((note) => note.isNotEmpty),
    ];
    return notes.isEmpty ? null : notes.join('\n\n');
  }

  /// 先建后删：创建失败时旧批注保持原样，成功后才清理被合并的旧记录。
  Future<Set<String>> _deleteAnnotations(
    Iterable<ReaderAnnotation> targets,
  ) async {
    final removed = <String>{};
    for (final annotation in targets) {
      try {
        await dataManager.deleteAnnotation(annotation.id);
        removed.add(annotation.id);
      } on Exception catch (e) {
        if (kDebugMode) {
          readerDebugLog(
            'ReaderAnnotationHandler: overlapping delete failed: $e',
          );
        }
      }
    }
    return removed;
  }

  /// 用内存结果立即驱动 UI；完整远端刷新仍由 load() 在适当入口执行。
  void _publish(List<ReaderAnnotation> annotations) {
    _annotations = annotations;
    onAnnotationsChanged();
  }

  /// 用户最近一次选择的高亮色，作为下一次新建高亮的默认值。
  String _preferredHighlightColor = ReaderHighlightPalette.defaultColor;

  static const Duration _undoWindow = Duration(seconds: 6);

  /// 创建高亮（保留被覆盖批注的已有备注，且先建后删防止异常丢数据）。
  Future<void> highlight(
    String selectedText,
    int startOffset,
    int endOffset,
    BuildContext context, {
    String? color,
  }) async {
    final effectiveColor = color ?? _preferredHighlightColor;
    if (color != null) {
      _preferredHighlightColor = color;
    }
    final chapter = chapterId;
    final overlapping = _findOverlapping(chapter, startOffset, endOffset);
    final preservedNote = _mergedNote(overlapping);
    try {
      final created = await dataManager.createAnnotation(
        itemId: itemId,
        chapterId: chapter,
        startOffset: startOffset,
        endOffset: endOffset,
        highlightText: selectedText,
        note: preservedNote,
        color: effectiveColor,
      );
      final replacedIds = await _deleteAnnotations(overlapping);
      _publish([
        ..._annotations.where(
          (a) => a.id != created.id && !replacedIds.contains(a.id),
        ),
        created,
      ]);
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
      ReaderHighlightPalette.colors.contains(color) ? color! : '#E0E0E0';

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
      final overlapping = _findOverlapping(chapter, startOffset, endOffset);
      try {
        final created = await dataManager.createAnnotation(
          itemId: itemId,
          chapterId: chapter,
          startOffset: startOffset,
          endOffset: endOffset,
          highlightText: selectedText,
          note: _mergedNote(overlapping, primary: result.note),
          color: result.color,
        );
        final replacedIds = await _deleteAnnotations(overlapping);
        _publish([
          ..._annotations.where(
            (a) => a.id != created.id && !replacedIds.contains(a.id),
          ),
          created,
        ]);
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

  /// 删除批注：含笔记时先确认，随后进入 6 秒可撤销的软删除窗口。
  Future<void> delete(ReaderAnnotation annotation, BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final hasNote = annotation.note?.trim().isNotEmpty == true;
    if (hasNote) {
      final confirmed = await showWorkstationConfirmDialog(
        context,
        title: l10n.readerDeleteAnnotation,
        message: l10n.readerDeleteAnnotationNoteConfirm,
        confirmLabel: l10n.readerDeleteAnnotation,
        destructive: true,
      );
      if (!confirmed || !context.mounted) {
        return;
      }
    }
    await _commitAllPendingDeletes();
    if (!context.mounted) {
      return;
    }
    final index = _annotations.indexWhere((a) => a.id == annotation.id);
    if (index < 0) {
      return;
    }
    _pendingDeletes[annotation.id] = (
      annotation: annotation,
      index: index,
      timer: Timer(_undoWindow, () => unawaited(_commitDelete(annotation.id))),
      context: context,
    );
    _publish(_annotations.where((a) => a.id != annotation.id).toList());
    showReaderSnackBar(
      context,
      l10n.readerAnnotationDeleted,
      duration: _undoWindow,
      action: SnackBarAction(
        label: l10n.readerUndo,
        onPressed: () => undoDelete(annotation.id),
      ),
    );
  }

  /// 6 秒窗口内撤销：不写数据库、不请求网络。
  void undoDelete(String annotationId) {
    final pending = _pendingDeletes.remove(annotationId);
    if (pending == null) {
      return;
    }
    pending.timer.cancel();
    final restored = [..._annotations];
    restored.insert(
      pending.index.clamp(0, restored.length),
      pending.annotation,
    );
    _publish(restored);
  }

  Future<void> _commitAllPendingDeletes() async {
    for (final id in _pendingDeletes.keys.toList()) {
      await _commitDelete(id);
    }
  }

  Future<void> _commitDelete(String annotationId) async {
    final pending = _pendingDeletes.remove(annotationId);
    if (pending == null) {
      return;
    }
    pending.timer.cancel();
    try {
      await dataManager.deleteAnnotation(annotationId);
    } on Exception catch (e) {
      if (kDebugMode) {
        readerDebugLog('ReaderAnnotationHandler: annotation delete failed: $e');
      }
      final restored = [..._annotations];
      restored.insert(
        pending.index.clamp(0, restored.length),
        pending.annotation,
      );
      _publish(restored);
      if (pending.context.mounted) {
        showReaderSnackBar(
          pending.context,
          AppLocalizations.of(pending.context).readerAnnotationDeleteFailed,
        );
      }
    }
  }

  /// 页面销毁时立即提交未到期的软删除，避免记录只留在内存。
  void dispose() {
    for (final id in _pendingDeletes.keys.toList()) {
      unawaited(_commitDelete(id));
    }
  }

  /// 原地切换高亮颜色，保留原备注与选区偏移。
  Future<void> updateColor(
    ReaderAnnotation annotation,
    String color,
    BuildContext context,
  ) async {
    try {
      await dataManager.updateAnnotation(
        annotationId: annotation.id,
        note: annotation.note,
        color: color,
      );
      _publish([
        for (final item in _annotations)
          if (item.id == annotation.id)
            ReaderAnnotation(
              id: item.id,
              readerItemId: item.readerItemId,
              startOffset: item.startOffset,
              endOffset: item.endOffset,
              chapterId: item.chapterId,
              highlightText: item.highlightText,
              note: item.note,
              color: color,
              createdAt: item.createdAt,
            )
          else
            item,
      ]);
    } on Exception catch (e) {
      if (kDebugMode) {
        readerDebugLog(
          'ReaderAnnotationHandler: annotation recolor failed: $e',
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
        _publish([
          for (final item in _annotations)
            if (item.id == annotation.id)
              ReaderAnnotation(
                id: item.id,
                readerItemId: item.readerItemId,
                startOffset: item.startOffset,
                endOffset: item.endOffset,
                chapterId: item.chapterId,
                highlightText: item.highlightText,
                note: result.note,
                color: result.color,
                createdAt: item.createdAt,
              )
            else
              item,
        ]);
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
        for (final colorHex in ReaderHighlightPalette.colors)
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
