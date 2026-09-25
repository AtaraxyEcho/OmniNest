import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/application/movie_detail_action_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/movie_feedback.dart';
import 'package:omninest/features/video/presentation/widgets/movie_poster_image.dart';

part 'movie_detail_page_sections.dart';
part 'movie_detail_page_tabs.dart';
part 'movie_detail_page_subtitles.dart';

/// 影片详情页：暗色金调整页视图（对应 Movies Module Design/components/Detail.tsx）。
///
/// 压题图与内容同处一个滚动域（-64px 海报叠压不会被滚动区上边缘裁切），
/// 结构：压题图（BACK / EDIT / 收藏）→ 海报+元信息 → PLAY →
/// overview / versions / subtitles 三标签。路由 `/video/:videoId`。
class MovieDetailPage extends ConsumerWidget {
  const MovieDetailPage({required this.videoItemId, super.key});

  final String videoItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(movieDetailProvider(videoItemId));
    return detail.when(
      loading:
          () => const _DarkScaffold(
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      error:
          (error, _) => _DarkScaffold(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      movieErrorMessage(error),
                      textAlign: TextAlign.center,
                      style: MovieDetailTheme.body(
                        14,
                        color: MovieDetailTheme.secondaryText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: MovieRedesignPalette.borderRadius,
                      side: const BorderSide(color: MovieDetailTheme.mutedText),
                    ),
                    child: InkWell(
                      onTap:
                          () =>
                              ref.invalidate(movieDetailProvider(videoItemId)),
                      borderRadius: MovieRedesignPalette.borderRadius,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          AppLocalizations.of(context).coreRetry,
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: AppTypography.bodySmall,
                            color: MovieDetailTheme.secondaryText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      data: (item) => _MovieDetailView(key: ValueKey(item.id), item: item),
    );
  }
}

class _DarkScaffold extends StatelessWidget {
  const _DarkScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MovieDetailTheme.background,
      child: Scaffold(
        backgroundColor: MovieDetailTheme.background,
        body: ColoredBox(color: MovieDetailTheme.background, child: child),
      ),
    );
  }
}

enum _DetailTab { overview, versions, subtitles }

class _MovieDetailView extends ConsumerStatefulWidget {
  const _MovieDetailView({required this.item, super.key});

  final MovieVideoItem item;

  @override
  ConsumerState<_MovieDetailView> createState() => _MovieDetailViewState();
}

class _MovieDetailViewState extends ConsumerState<_MovieDetailView> {
  _DetailTab _tab = _DetailTab.overview;
  bool _editMode = false;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _overviewController = TextEditingController();
  String? _initializedForId;

  @override
  void dispose() {
    _titleController.dispose();
    _overviewController.dispose();
    super.dispose();
  }

  /// 进入编辑态时按当前详情初始化输入框（按条目 id 防重初始化）。
  void _ensureControllers(MovieVideoItem item) {
    if (_initializedForId == item.id) {
      return;
    }
    _initializedForId = item.id;
    _titleController.text = item.title;
    _overviewController.text = item.overview ?? '';
  }

  Future<void> _saveEdits(MovieVideoItem item) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      return;
    }
    final actions = ref.read(movieDetailActionProvider.notifier);
    try {
      await actions.save(
        () => ref
            .read(movieCenterControllerProvider.notifier)
            .updateMetadata(
              videoItemId: item.id,
              title: title,
              originalTitle: item.originalTitle,
              releaseDate: item.releaseDate,
              overview: _overviewController.text.trim(),
              posterFileId: item.posterFileId,
              backdropFileId: item.backdropFileId,
              runtimeSeconds: item.runtimeSeconds,
              metadataStatus: item.metadataStatus,
            ),
      );
      if (!mounted) {
        return;
      }
      ref.invalidate(movieDetailProvider(item.id));
      setState(() => _editMode = false);
    } on Exception catch (error) {
      if (mounted) {
        showMovieFeedback(context, movieErrorMessage(error), isError: true);
      }
    }
  }

  Future<void> _toggleFavorite(bool current) async {
    final actions = ref.read(movieDetailActionProvider.notifier);
    try {
      await actions.toggleFavorite(
        current: current,
        apply:
            (next) => ref
                .read(movieCenterControllerProvider.notifier)
                .toggleFavorite(widget.item, favorite: next),
      );
      if (!mounted) {
        return;
      }
      ref.invalidate(videoFavoriteStatusProvider(widget.item.id));
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      showMovieFeedback(context, movieErrorMessage(error), isError: true);
    }
  }

  Future<void> _pickAndUploadSubtitle() async {
    final l10n = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['vtt', 'srt', 'ass', 'ssa', 'ttml', 'sub'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null || file.bytes == null || !mounted) {
      return;
    }
    final language = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _SubtitleLanguageDialog(fileName: file.name),
    );
    if (language == null || language.isEmpty || !mounted) {
      return;
    }
    final actions = ref.read(movieDetailActionProvider.notifier);
    try {
      await actions.upload(
        () => ref
            .read(movieCenterControllerProvider.notifier)
            .uploadSubtitle(
              videoItemId: widget.item.id,
              fileName: file.name,
              bytes: file.bytes!,
              mimeType: _subtitleMime(file.extension),
              language: language,
            ),
      );
      if (!mounted) {
        return;
      }
      ref.invalidate(movieSubtitlesProvider(widget.item.id));
      showMovieFeedback(context, l10n.videoSubtitleUploaded);
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      showMovieFeedback(context, movieErrorMessage(error), isError: true);
    }
  }

  String _subtitleMime(String? ext) {
    return switch (ext?.toLowerCase()) {
      'vtt' => 'text/vtt',
      'srt' => 'application/x-subrip',
      'ttml' => 'application/ttml+xml',
      _ => 'text/plain',
    };
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    _ensureControllers(item);
    final canEdit =
        ref
            .watch(authSessionProvider)
            .asData
            ?.value
            .user
            ?.permissions
            .contains('media:write') ??
        false;
    final favoriteAsync = ref.watch(videoFavoriteStatusProvider(item.id));
    final actionState = ref.watch(movieDetailActionProvider);
    final favorited =
        actionState.favoritedOverride ?? favoriteAsync.asData?.value ?? false;
    return Scaffold(
      backgroundColor: MovieDetailTheme.background,
      // 压题图与内容同处一个滚动域：-64px 海报叠压不会被滚动区上边缘裁切。
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Backdrop(
              backdropUrl: item.backdropImageUrl ?? item.posterImageUrl,
              backdropCacheKey: 'movie-backdrop:${item.id}',
              favorited: favorited,
              canEdit: canEdit && !actionState.saving,
              editMode: _editMode,
              saving: actionState.saving,
              onBack: () => exitDetailRoute(context, fallbackRoute: '/video'),
              onToggleEdit: () {
                if (_editMode) {
                  unawaited(_saveEdits(item));
                } else {
                  setState(() {
                    _editMode = true;
                  });
                }
              },
              onToggleFavorite: () => unawaited(_toggleFavorite(favorited)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1024),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Transform.translate(
                        offset: const Offset(0, -64),
                        child: _PosterMetaRow(
                          item: item,
                          editMode: _editMode,
                          titleController: _titleController,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _PlayButton(item: item),
                      const SizedBox(height: 32),
                      _TabBar(
                        active: _tab,
                        onSelect: (tab) => setState(() => _tab = tab),
                      ),
                      const SizedBox(height: 24),
                      switch (_tab) {
                        _DetailTab.overview => _OverviewTab(
                          item: item,
                          editMode: _editMode,
                          overviewController: _overviewController,
                        ),
                        _DetailTab.versions => _VersionsTab(item: item),
                        _DetailTab.subtitles => _SubtitlesTab(
                          item: item,
                          uploading: actionState.uploading,
                          onUpload: _pickAndUploadSubtitle,
                        ),
                      },
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
