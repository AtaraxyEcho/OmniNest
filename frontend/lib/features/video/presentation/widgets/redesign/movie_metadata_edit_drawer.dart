import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/movie_feedback.dart';

/// 从右侧滑出的元数据编辑抽屉（暗色金调，替代旧元数据编辑路由页）。
///
/// 保存走元数据 API 并保留 poster/backdrop/状态等未编辑字段；
/// 保存成功后失效详情缓存并静默刷新中心数据。
Future<void> showMovieMetadataEditor(
  BuildContext context,
  MovieVideoItem item,
) async {
  final l10n = AppLocalizations.of(context);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l10n.videoDetailEdit,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder:
        (dialogContext, animation, secondaryAnimation) => Align(
          alignment: Alignment.centerRight,
          child: MovieMetadataEditPanel(item: item),
        ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// 右侧元数据编辑面板：名称 / 原名 / 年份 / 时长 / 简介。
class MovieMetadataEditPanel extends ConsumerStatefulWidget {
  const MovieMetadataEditPanel({required this.item, super.key});

  final MovieVideoItem item;

  @override
  ConsumerState<MovieMetadataEditPanel> createState() =>
      _MovieMetadataEditPanelState();
}

class _MovieMetadataEditPanelState
    extends ConsumerState<MovieMetadataEditPanel> {
  late final TextEditingController _titleController;
  late final TextEditingController _originalTitleController;
  late final TextEditingController _yearController;
  late final TextEditingController _runtimeController;
  late final TextEditingController _overviewController;
  bool _saving = false;

  bool _hydrated = false;
  bool _userEdited = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _titleController = TextEditingController(text: item.title);
    _originalTitleController = TextEditingController(
      text: item.originalTitle ?? '',
    );
    _yearController = TextEditingController(text: item.year);
    _runtimeController = TextEditingController(
      text:
          item.runtimeSeconds != null && item.runtimeSeconds! > 0
              ? (item.runtimeSeconds! / 60).round().toString()
              : '',
    );
    _overviewController = TextEditingController(text: item.overview ?? '');
    // 列表 DTO 不含简介等字段：打开后拉取完整详情回填（用户已输入则不覆盖）。
    _hydrateFromDetail();
  }

  Future<void> _hydrateFromDetail() async {
    try {
      final detail = await ref.read(movieDetailProvider(widget.item.id).future);
      if (!mounted || _userEdited || _hydrated) {
        return;
      }
      setState(() {
        _hydrated = true;
        if (_titleController.text.isEmpty) {
          _titleController.text = detail.title;
        }
        if (_originalTitleController.text.isEmpty &&
            detail.originalTitle != null) {
          _originalTitleController.text = detail.originalTitle!;
        }
        if (_yearController.text.isEmpty) {
          _yearController.text = detail.year;
        }
        if (_runtimeController.text.isEmpty &&
            detail.runtimeSeconds != null &&
            detail.runtimeSeconds! > 0) {
          _runtimeController.text =
              (detail.runtimeSeconds! / 60).round().toString();
        }
        if (_overviewController.text.isEmpty && detail.overview != null) {
          _overviewController.text = detail.overview!;
        }
      });
    } on Exception {
      // 回填失败保持列表级数据，用户仍可手动编辑。
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _originalTitleController.dispose();
    _yearController.dispose();
    _runtimeController.dispose();
    _overviewController.dispose();
    super.dispose();
  }

  void _markEdited() {
    _userEdited = true;
  }

  Future<void> _save() async {
    final item = widget.item;
    final title = _titleController.text.trim();
    if (title.isEmpty || _saving) {
      return;
    }
    final year = int.tryParse(_yearController.text.trim());
    final runtimeMinutes = int.tryParse(_runtimeController.text.trim());
    setState(() => _saving = true);
    try {
      await ref
          .read(movieApiProvider)
          .updateMetadata(
            videoItemId: item.id,
            title: title,
            originalTitle:
                _originalTitleController.text.trim().isEmpty
                    ? item.originalTitle
                    : _originalTitleController.text.trim(),
            releaseDate: year == null ? item.releaseDate : DateTime(year),
            overview: _overviewController.text.trim(),
            posterFileId: item.posterFileId,
            backdropFileId: item.backdropFileId,
            runtimeSeconds:
                runtimeMinutes == null
                    ? item.runtimeSeconds
                    : runtimeMinutes * 60,
            metadataStatus: item.metadataStatus,
          );
      if (!mounted) {
        return;
      }
      ref.invalidate(movieDetailProvider(item.id));
      unawaited(
        ref.read(movieCenterControllerProvider.notifier).refreshForRealtime(),
      );
      Navigator.of(context).pop();
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      showMovieFeedback(context, movieErrorMessage(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final l10n = AppLocalizations.of(context);
    return Material(
      color: MovieDetailTheme.background,
      child: SafeArea(
        left: false,
        child: SizedBox(
          width: 384,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.videoDetailEdit,
                        style: text
                            .mono(size: 16, color: palette.foreground)
                            .copyWith(letterSpacing: 2),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: palette.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: palette.border),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fieldLabel(text, l10n.videoSourceName),
                      const SizedBox(height: 4),
                      _drawerTextField(
                        text,
                        controller: _titleController,
                        onChanged: (_) => _markEdited(),
                      ),
                      const SizedBox(height: 14),
                      _fieldLabel(text, l10n.videoMetaFieldOriginalTitle),
                      const SizedBox(height: 4),
                      _drawerTextField(
                        text,
                        controller: _originalTitleController,
                      ),
                      const SizedBox(height: 14),
                      _fieldLabel(text, l10n.videoMetaFieldYear),
                      const SizedBox(height: 4),
                      _drawerTextField(
                        text,
                        controller: _yearController,
                        onChanged: (_) => _markEdited(),
                      ),
                      const SizedBox(height: 14),
                      _fieldLabel(text, l10n.videoMetaFieldRuntimeMinutes),
                      const SizedBox(height: 4),
                      _drawerTextField(
                        text,
                        controller: _runtimeController,
                        onChanged: (_) => _markEdited(),
                      ),
                      const SizedBox(height: 14),
                      _fieldLabel(text, l10n.videoMetaFieldOverview),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _overviewController,
                        maxLines: 5,
                        style: text.body(
                          size: 14,
                          color: palette.foreground,
                          height: 1.6,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: MovieDetailTheme.surface,
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: palette.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: MovieDetailTheme.accent,
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: Material(
                          color: palette.primary,
                          borderRadius: MovieRedesignPalette.borderRadius,
                          child: InkWell(
                            onTap: _saving ? null : () => unawaited(_save()),
                            borderRadius: MovieRedesignPalette.borderRadius,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Center(
                                child:
                                    _saving
                                        ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                        : Text(
                                          l10n.videoDetailSave,
                                          style: text
                                              .mono(
                                                size: 14,
                                                color: palette.onPrimary,
                                              )
                                              .copyWith(letterSpacing: 2),
                                        ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(MovieRedesignText text, String label) {
    return Text(
      label,
      style: text
          .mono(size: 10, color: MovieDetailTheme.mutedText)
          .copyWith(letterSpacing: 1),
    );
  }

  Widget _drawerTextField(
    MovieRedesignText text, {
    required TextEditingController controller,
    ValueChanged<String>? onChanged,
  }) {
    final palette = context.movieRedesign;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: text.body(size: 14, color: palette.foreground),
      decoration: InputDecoration(
        filled: true,
        fillColor: MovieDetailTheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: MovieRedesignPalette.borderRadius,
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: MovieRedesignPalette.borderRadius,
          borderSide: BorderSide(color: MovieDetailTheme.accent),
        ),
      ),
    );
  }
}
