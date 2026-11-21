import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/video/application/movie_metadata_commands.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/movie_feedback.dart';
import 'package:omninest/features/video/presentation/widgets/movie_poster_image.dart';

/// 从右侧滑出的元数据编辑抽屉（暗色金调，替代旧元数据编辑路由页）。
///
/// 保存走元数据 API 并保留 poster/backdrop/状态等未编辑字段；
/// 保存成功后失效详情缓存并静默刷新中心数据。
Future<void> showMovieMetadataEditor(
  BuildContext context,
  MovieVideoItem item,
) async {
  final l10n = AppLocalizations.of(context);
  await showWorkstationGeneralDialog<void>(
    context: context,
    dismissible: true,
    barrierLabel: l10n.videoDetailEdit,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder:
        (dialogContext, animation, secondaryAnimation) => Align(
          alignment: Alignment.centerRight,
          child: MovieMetadataEditPanel(item: item),
        ),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
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

/// 右侧元数据编辑面板：影片字段与参考稿一致，剧集保留独立可写字段。
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
  late final TextEditingController _genreController;
  late final TextEditingController _ratingController;
  late final TextEditingController _castController;
  late final TextEditingController _posterUrlController;
  bool _saving = false;

  bool _hydrated = false;
  bool _userEdited = false;

  bool get _isMovie => widget.item.movieId != null;
  bool get _canRestoreOriginal =>
      widget.item.metadata['manualMetadataOriginal'] is Map;

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
              ? _formatRuntime(item.runtimeSeconds!)
              : '',
    );
    _overviewController = TextEditingController(text: item.overview ?? '');
    _genreController = TextEditingController(text: item.genres.join(', '));
    _ratingController = TextEditingController(
      text: item.rating?.toStringAsFixed(1) ?? '',
    );
    _castController = TextEditingController(
      text: item.castMembers.map((member) => member.name).join(', '),
    );
    _posterUrlController = TextEditingController(
      text: item.metadata['manualPosterUrl']?.toString() ?? '',
    );
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
          _runtimeController.text = _formatRuntime(detail.runtimeSeconds!);
        }
        if (_overviewController.text.isEmpty && detail.overview != null) {
          _overviewController.text = detail.overview!;
        }
        if (_genreController.text.isEmpty && detail.genres.isNotEmpty) {
          _genreController.text = detail.genres.join(', ');
        }
        if (_ratingController.text.isEmpty && detail.rating != null) {
          _ratingController.text = detail.rating!.toStringAsFixed(1);
        }
        if (_castController.text.isEmpty && detail.castMembers.isNotEmpty) {
          _castController.text = detail.castMembers
              .map((member) => member.name)
              .join(', ');
        }
        if (_posterUrlController.text.isEmpty) {
          _posterUrlController.text =
              detail.metadata['manualPosterUrl']?.toString() ?? '';
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
    _genreController.dispose();
    _ratingController.dispose();
    _castController.dispose();
    _posterUrlController.dispose();
    super.dispose();
  }

  void _markEdited() {
    if (!_userEdited) {
      _userEdited = true;
    }
    setState(() {});
  }

  Future<void> _save() async {
    final item = widget.item;
    final title = _titleController.text.trim();
    final year = int.tryParse(_yearController.text.trim());
    final rating = double.tryParse(_ratingController.text.trim());
    final runtimeSeconds = _parseRuntime(_runtimeController.text);
    if (title.isEmpty ||
        _saving ||
        (_isMovie &&
            (_yearController.text.trim().length != 4 ||
                year == null ||
                rating == null ||
                !rating.isFinite ||
                rating < 0 ||
                rating > 10 ||
                (_runtimeController.text.trim().isNotEmpty &&
                    runtimeSeconds == null)))) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(movieMetadataCommandsProvider)
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
                _isMovie && _runtimeController.text.trim().isEmpty
                    ? null
                    : runtimeSeconds ?? item.runtimeSeconds,
            clearRuntime: _isMovie && _runtimeController.text.trim().isEmpty,
            genres:
                _isMovie ? _splitCommaSeparated(_genreController.text) : null,
            rating: _isMovie ? rating : null,
            cast: _isMovie ? _splitCommaSeparated(_castController.text) : null,
            posterUrl:
                _isMovie
                    ? (_posterUrlController.text.trim().isNotEmpty
                        ? _posterUrlController.text.trim()
                        : item.metadata['manualPosterUrl']?.toString())
                    : null,
            metadataStatus: item.metadataStatus,
          );
      if (!mounted) {
        return;
      }
      ref.invalidate(movieDetailProvider(item.id));
      unawaited(
        ref.read(movieCenterControllerProvider.notifier).refreshForRealtime(),
      );
      showMovieFeedback(context, l10n.videoMetadataSaved);
      Navigator.of(context).pop();
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      showMovieFeedback(
        context,
        movieErrorMessage(error, AppLocalizations.of(context)),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _restoreOriginal() async {
    if (_saving) {
      return;
    }
    final item = widget.item;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(movieMetadataCommandsProvider)
          .updateMetadata(
            videoItemId: item.id,
            title:
                _titleController.text.trim().isEmpty
                    ? item.title
                    : _titleController.text.trim(),
            restoreOriginal: true,
          );
      if (!mounted) {
        return;
      }
      ref.invalidate(movieDetailProvider(item.id));
      unawaited(
        ref.read(movieCenterControllerProvider.notifier).refreshForRealtime(),
      );
      showMovieFeedback(context, l10n.readerMetadataRestored);
      Navigator.of(context).pop();
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      showMovieFeedback(context, movieErrorMessage(error, l10n), isError: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  static String _formatRuntime(int runtimeSeconds) {
    final minutes = (runtimeSeconds / 60).round();
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) {
      return '${remainder}m';
    }
    return '${hours}h ${remainder}m';
  }

  static int? _parseRuntime(String input) {
    final value = input.trim().toLowerCase();
    if (value.isEmpty) {
      return null;
    }
    final pattern = RegExp(r'^(?:(\d+)\s*h)?\s*(?:(\d+)\s*m)?$');
    final match = pattern.firstMatch(value);
    if (match != null && (match.group(1) != null || match.group(2) != null)) {
      final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
      final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
      final totalMinutes = hours * 60 + minutes;
      return totalMinutes > 0 ? totalMinutes * 60 : null;
    }
    final minutes = int.tryParse(value);
    return minutes == null || minutes <= 0 ? null : minutes * 60;
  }

  static List<String> _splitCommaSeparated(String value) =>
      value
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toSet()
          .toList();

  @override
  Widget build(BuildContext context) {
    final palette = context.movieDetailPalette;
    final text = context.movieDetailText;
    final l10n = AppLocalizations.of(context);
    final panelWidth =
        MediaQuery.of(context).size.width.clamp(0, 520).toDouble();
    final parsedYear = int.tryParse(_yearController.text.trim());
    final parsedRating = double.tryParse(_ratingController.text.trim());
    final runtimeValid =
        _runtimeController.text.trim().isEmpty ||
        _parseRuntime(_runtimeController.text) != null;
    final canSave =
        _titleController.text.trim().isNotEmpty &&
        (!_isMovie ||
            (_yearController.text.trim().length == 4 &&
                parsedYear != null &&
                parsedRating != null &&
                parsedRating.isFinite &&
                parsedRating >= 0 &&
                parsedRating <= 10 &&
                runtimeValid));
    return Material(
      color: MovieDetailTheme.background,
      child: SafeArea(
        left: false,
        child: SizedBox(
          width: panelWidth,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.videoMetaEyebrow,
                            style: text
                                .mono(
                                  size: AppTypography.labelSmall,
                                  color: palette.mutedForeground,
                                )
                                .copyWith(letterSpacing: 1.5),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            l10n.videoMetaEditDetails,
                            style: text.body(
                              size: AppTypography.titleMedium,
                              color: palette.foreground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.videoClose,
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
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isMovie) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 92,
                              height: 132,
                              child: MoviePosterImage(
                                imageUrl:
                                    _posterUrlController.text.trim().isNotEmpty
                                        ? _posterUrlController.text.trim()
                                        : widget.item.posterImageUrl,
                                cacheKey: 'movie-poster:${widget.item.id}',
                                cacheWidth: MoviePosterImage.decodeWidth(
                                  context,
                                  92,
                                  cap: 276,
                                ),
                                fallback: ColoredBox(
                                  color: MovieDetailTheme.surface,
                                  child: Icon(
                                    Icons.movie_outlined,
                                    color: palette.mutedForeground,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _fieldLabel(text, l10n.videoMetaFieldTitle),
                                  const SizedBox(height: 4),
                                  _drawerTextField(
                                    text,
                                    controller: _titleController,
                                    onChanged: (_) => _markEdited(),
                                  ),
                                  const SizedBox(height: 12),
                                  _fieldLabel(text, l10n.videoMetaFieldGenre),
                                  const SizedBox(height: 4),
                                  _drawerTextField(
                                    text,
                                    controller: _genreController,
                                    onChanged: (_) => _markEdited(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _labeledField(
                                text,
                                l10n.videoMetaFieldYear,
                                _yearController,
                                onChanged: (_) => _markEdited(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _labeledField(
                                text,
                                l10n.videoMetaFieldRuntime,
                                _runtimeController,
                                onChanged: (_) => _markEdited(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _labeledField(
                                text,
                                l10n.videoMetaFieldRating,
                                _ratingController,
                                onChanged: (_) => _markEdited(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _labeledField(
                          text,
                          l10n.videoMetaFieldCast,
                          _castController,
                          onChanged: (_) => _markEdited(),
                        ),
                        const SizedBox(height: 14),
                        _labeledField(
                          text,
                          l10n.videoMetaFieldPosterUrl,
                          _posterUrlController,
                          onChanged: (_) => _markEdited(),
                        ),
                      ] else ...[
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
                        Row(
                          children: [
                            Expanded(
                              child: _labeledField(
                                text,
                                l10n.videoMetaFieldYear,
                                _yearController,
                                onChanged: (_) => _markEdited(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _labeledField(
                                text,
                                l10n.videoMetaFieldRuntimeMinutes,
                                _runtimeController,
                                onChanged: (_) => _markEdited(),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      _fieldLabel(text, l10n.videoMetaFieldOverview),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _overviewController,
                        maxLines: 5,
                        onChanged: (_) => _markEdited(),
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
                    ],
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: palette.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
                    if (_canRestoreOriginal)
                      TextButton.icon(
                        onPressed:
                            _saving
                                ? null
                                : () => unawaited(_restoreOriginal()),
                        icon: const Icon(Icons.undo_rounded, size: 16),
                        label: Text(l10n.readerRestoreOriginalMetadata),
                        style: TextButton.styleFrom(
                          foregroundColor: palette.mutedForeground,
                        ),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      child: Text(l10n.videoCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed:
                          _saving || !canSave ? null : () => unawaited(_save()),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.primary,
                        foregroundColor: palette.onPrimary,
                        shape: const RoundedRectangleBorder(),
                      ),
                      child:
                          _saving
                              ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : Text(l10n.videoDetailSave),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labeledField(
    MovieRedesignText text,
    String label,
    TextEditingController controller, {
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(text, label),
        const SizedBox(height: 4),
        _drawerTextField(text, controller: controller, onChanged: onChanged),
      ],
    );
  }

  Widget _fieldLabel(MovieRedesignText text, String label) {
    return Text(
      label,
      style: text
          // ignore: font_size_whitelist
          .mono(size: 10, color: MovieDetailTheme.mutedText)
          .copyWith(letterSpacing: 1),
    );
  }

  Widget _drawerTextField(
    MovieRedesignText text, {
    required TextEditingController controller,
    ValueChanged<String>? onChanged,
  }) {
    final palette = context.movieDetailPalette;
    return TextField(
      controller: controller,
      cursorColor: MovieDetailTheme.accent,
      onChanged: onChanged,
      style: text.body(
        size: AppTypography.bodyLarge,
        color: palette.foreground,
      ),
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
