import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
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
    this.chapters = const [],
  });

  final String itemId;
  String chapterId;
  final ReaderDataManager dataManager;
  ReaderViewSettings settings;
  final VoidCallback onAnnotationsChanged;

  /// 章节列表，用于在全书批注模式下查找章节标题。
  List<ReaderChapter> chapters;

  List<ReaderAnnotation> _annotations = [];

  List<ReaderAnnotation> get annotations => _annotations;

  List<ReaderAnnotation> get chapterAnnotations =>
      annotationsForChapter(chapterId);

  /// 指定章节的批注（连续滚动窗口内邻章渲染用）。
  List<ReaderAnnotation> annotationsForChapter(String id) =>
      _annotations.where((a) => a.chapterId == id).toList();

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
  Future<void> _deleteOverlapping(int startOffset, int endOffset) async {
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
    try {
      await _deleteOverlapping(startOffset, endOffset);
      await dataManager.createAnnotation(
        itemId: itemId,
        chapterId: chapterId,
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
      if (kDebugMode) {
        readerDebugLog(
          'ReaderAnnotationHandler: highlight creation failed: $e',
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

  /// 创建批注（弹出输入弹窗）。
  Future<void> annotate(
    String selectedText,
    int startOffset,
    int endOffset,
    BuildContext context,
  ) async {
    final l10n = AppLocalizations.of(context);
    final noteController = TextEditingController();
    String selectedColor = '#E0E0E0';
    bool noteEmpty = true;

    final result = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text(l10n.readerAddAnnotation),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: SingleChildScrollView(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            selectedText,
                            style: const TextStyle(
                              fontSize: AppTypography.bodyMedium,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children:
                          _presetColors.map((colorHex) {
                            final isSelected = selectedColor == colorHex;
                            final color = parseAnnotationColor(colorHex);
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: InkWell(
                                onTap:
                                    () => setState(() {
                                      selectedColor = colorHex;
                                    }),
                                customBorder: const CircleBorder(),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: color,
                                    border: Border.all(
                                      color:
                                          isSelected
                                              ? Theme.of(
                                                context,
                                              ).colorScheme.outline
                                              : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child:
                                      isSelected
                                          ? Icon(
                                            Icons.check,
                                            size: 16,
                                            color: Colors.black,
                                          )
                                          : null,
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      onChanged: (v) {
                        setState(() => noteEmpty = v.trim().isEmpty);
                      },
                      decoration: InputDecoration(
                        hintText: l10n.readerAnnotationHint,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      MaterialLocalizations.of(context).cancelButtonLabel,
                    ),
                  ),
                  FilledButton(
                    onPressed:
                        noteEmpty ? null : () => Navigator.pop(ctx, true),
                    child: Text(
                      MaterialLocalizations.of(context).okButtonLabel,
                    ),
                  ),
                ],
              );
            },
          ),
    );

    if (result == true && noteController.text.trim().isNotEmpty) {
      try {
        await _deleteOverlapping(startOffset, endOffset);
        await dataManager.createAnnotation(
          itemId: itemId,
          chapterId: chapterId,
          startOffset: startOffset,
          endOffset: endOffset,
          highlightText: selectedText,
          note: noteController.text.trim(),
          color: selectedColor,
        );
        await load();
      } on Exception catch (e) {
        if (kDebugMode) {
          readerDebugLog(
            'ReaderAnnotationHandler: annotation creation failed: $e',
          );
        }
      }
    }
    noteController.dispose();
  }

  /// 删除批注。
  Future<void> delete(ReaderAnnotation annotation) async {
    try {
      await dataManager.deleteAnnotation(annotation.id);
      await load();
    } on Exception catch (e) {
      if (kDebugMode) {
        readerDebugLog('ReaderAnnotationHandler: annotation delete failed: $e');
      }
    }
  }

  /// 编辑批注备注。
  Future<void> edit(ReaderAnnotation annotation, BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final noteController = TextEditingController(text: annotation.note);

    final result = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l10n.readerEditAnnotation),
            content: TextField(
              controller: noteController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: l10n.readerAnnotationHint,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(MaterialLocalizations.of(context).okButtonLabel),
              ),
            ],
          ),
    );

    if (result == true && noteController.text.trim().isNotEmpty) {
      try {
        await dataManager.updateAnnotation(
          annotationId: annotation.id,
          note: noteController.text.trim(),
        );
        await load();
      } on Exception catch (e) {
        if (kDebugMode) {
          readerDebugLog('ReaderAnnotationHandler: annotation edit failed: $e');
        }
      }
    }
    noteController.dispose();
  }

  /// 构建由阅读器自适应面板承载的批注内容。
  Widget buildPanel(BuildContext context) {
    return ReaderAnnotationPanel(
      annotations: chapterAnnotations,
      allAnnotations: _annotations,
      chapters: chapters,
      settings: settings,
      embedded: true,
      onDelete: (annotation) async {
        await delete(annotation);
      },
      onEdit: (annotation) {
        edit(annotation, context);
      },
    );
  }
}
