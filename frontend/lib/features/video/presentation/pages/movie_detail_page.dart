import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/movie_feedback.dart';

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
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          'RETRY',
                          style: TextStyle(
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
    return Scaffold(backgroundColor: MovieDetailTheme.background, body: child);
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
  bool _saving = false;
  bool _uploading = false;
  bool? _favoritedOverride;
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
    if (title.isEmpty || _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      // 走控制器以联动中心数据刷新，避免列表页标题停留旧值。
      await ref
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
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _toggleFavorite(bool current) async {
    final next = !current;
    setState(() => _favoritedOverride = next);
    try {
      // 走控制器刷新收藏列表等中心数据，收藏分区 pop 回来即时反映。
      await ref
          .read(movieCenterControllerProvider.notifier)
          .toggleFavorite(widget.item, favorite: next);
      if (!mounted) {
        return;
      }
      ref.invalidate(videoFavoriteStatusProvider(widget.item.id));
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _favoritedOverride = current);
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
    setState(() => _uploading = true);
    try {
      await ref
          .read(movieCenterControllerProvider.notifier)
          .uploadSubtitle(
            videoItemId: widget.item.id,
            fileName: file.name,
            bytes: file.bytes!,
            mimeType: _subtitleMime(file.extension),
            language: language,
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
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
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
    final favorited =
        _favoritedOverride ?? favoriteAsync.asData?.value ?? false;
    return Scaffold(
      backgroundColor: MovieDetailTheme.background,
      // 压题图与内容同处一个滚动域：-64px 海报叠压不会被滚动区上边缘裁切。
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Backdrop(
              backdropUrl: item.backdropImageUrl ?? item.posterImageUrl,
              favorited: favorited,
              canEdit: canEdit && !_saving,
              editMode: _editMode,
              saving: _saving,
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/video');
                }
              },
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
                          uploading: _uploading,
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

class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.backdropUrl,
    required this.favorited,
    required this.canEdit,
    required this.editMode,
    required this.saving,
    required this.onBack,
    required this.onToggleEdit,
    required this.onToggleFavorite,
  });

  final String? backdropUrl;
  final bool favorited;
  final bool canEdit;
  final bool editMode;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onToggleEdit;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 256,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdropUrl != null && backdropUrl!.isNotEmpty)
            Image.network(
              backdropUrl!,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.medium,
              errorBuilder:
                  (context, error, stackTrace) =>
                      const ColoredBox(color: MovieDetailTheme.surface),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }
                return const ColoredBox(color: MovieDetailTheme.surface);
              },
            )
          else
            const ColoredBox(color: MovieDetailTheme.surface),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.5, 1],
                colors: [
                  Colors.black26,
                  Colors.black54,
                  MovieDetailTheme.background,
                ],
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 20,
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('←', style: MovieDetailBackTextStyle()),
                      const SizedBox(width: 8),
                      Text(
                        l10n.videoDetailBack,
                        style: MovieDetailTheme.mono(
                          AppTypography.bodySmall,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 20,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canEdit)
                  Material(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: MovieRedesignPalette.borderRadius,
                    child: InkWell(
                      onTap: onToggleEdit,
                      borderRadius: MovieRedesignPalette.borderRadius,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: MovieRedesignPalette.borderRadius,
                          border: Border.all(
                            width: 1.2,
                            color:
                                editMode
                                    ? MovieDetailTheme.accent
                                    : Colors.white24,
                          ),
                        ),
                        child: Text(
                          saving
                              ? '…'
                              : editMode
                              ? l10n.videoDetailSave
                              : l10n.videoDetailEdit,
                          style: MovieDetailTheme.mono(
                            12,
                            color:
                                editMode
                                    ? MovieDetailTheme.accent
                                    : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                Material(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: onToggleFavorite,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        favorited
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 22,
                        color:
                            favorited ? MovieDetailTheme.accent : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 深链返回箭头的等宽文字样式。
class MovieDetailBackTextStyle extends TextStyle {
  const MovieDetailBackTextStyle()
    : super(
        inherit: true,
        fontFamily: 'JetBrainsMono',
        fontFamilyFallback: const ['NotoSansSC'],
        fontSize: AppTypography.bodySmall,
        color: MovieDetailTheme.secondaryText,
      );
}

class _PosterMetaRow extends StatelessWidget {
  const _PosterMetaRow({
    required this.item,
    required this.editMode,
    required this.titleController,
  });

  final MovieVideoItem item;
  final bool editMode;
  final TextEditingController titleController;

  @override
  Widget build(BuildContext context) {
    final director =
        item.crewMembers
            .where((member) => member.job?.toLowerCase() == 'director')
            .map((member) => member.name)
            .firstOrNull;
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 112,
          height: 160,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: MovieDetailTheme.border),
          ),
          child: _CoverImage(url: item.posterImageUrl),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (editMode)
                  TextField(
                    controller: titleController,
                    style: MovieDetailTheme.serif(
                      30,
                      color: MovieDetailTheme.foreground,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: MovieDetailTheme.accent),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: MovieDetailTheme.accent),
                      ),
                    ),
                  )
                else
                  Text(
                    item.title,
                    style: MovieDetailTheme.serif(
                      AppTypography.headlineLarge,
                      height: 1.15,
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (item.rating != null)
                      Text(
                        item.rating!.toStringAsFixed(1),
                        style: MovieDetailTheme.mono(
                          12,
                          color: MovieDetailTheme.accent,
                        ),
                      ),
                    Text(
                      item.year,
                      style: MovieDetailTheme.mono(AppTypography.bodySmall),
                    ),
                    if (item.runtimeSeconds != null && item.runtimeSeconds! > 0)
                      Text(
                        item.runtimeText,
                        style: MovieDetailTheme.mono(AppTypography.bodySmall),
                      ),
                    for (final genre in item.genres.take(3))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: MovieDetailTheme.border),
                        ),
                        child: Text(
                          genre,
                          style: MovieDetailTheme.mono(AppTypography.bodySmall),
                        ),
                      ),
                    _StatusChip(status: item.metadataStatus),
                  ],
                ),
                const SizedBox(height: 8),
                if (director != null && director.isNotEmpty)
                  Text(
                    '${l10n.videoDetailDirector} ${director.toUpperCase()}',
                    style: MovieDetailTheme.mono(AppTypography.bodySmall),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final resolved = url;
    if (resolved == null || resolved.isEmpty) {
      return const ColoredBox(color: MovieDetailTheme.surface);
    }
    return Image.network(
      resolved,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.medium,
      errorBuilder:
          (context, error, stackTrace) =>
              const ColoredBox(color: MovieDetailTheme.surface),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return const ColoredBox(color: MovieDetailTheme.surface);
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toUpperCase();
    final (color, hasBackground) = switch (normalized) {
      'MATCHED' => (MovieDetailTheme.mutedText, false),
      'PENDING' => (MovieDetailTheme.statusPending, true),
      _ => (MovieDetailTheme.statusFailed, true),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:
            hasBackground ? color.withValues(alpha: 0.10) : Colors.transparent,
      ),
      child: Text(
        normalized,
        style: MovieDetailTheme.mono(AppTypography.bodySmall, color: color),
      ),
    );
  }
}

class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.item});

  final MovieVideoItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(movieItemHistoryProvider(item.id));
    final progress = history.asData?.value?.progressPercent ?? 0;
    final showProgress = progress > 0 && progress < 100;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: MovieDetailTheme.foreground,
        child: InkWell(
          onTap: () => context.push('/video/${item.id}/play'),
          hoverColor: MovieDetailTheme.accent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(size: const Size(10, 12), painter: _PlayGlyph()),
                const SizedBox(width: 12),
                Text(
                  l10n.videoDetailPlay,
                  style: MovieDetailTheme.mono(
                    14,
                    color: MovieDetailTheme.background,
                    letterSpacing: 2,
                  ),
                ),
                if (showProgress)
                  Text(
                    ' (${progress.round()}%)',
                    style: MovieDetailTheme.mono(
                      12,
                      color: MovieDetailTheme.background,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayGlyph extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, size.height / 2)
          ..lineTo(0, size.height)
          ..close();
    canvas.drawPath(path, Paint()..color = MovieDetailTheme.background);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.active, required this.onSelect});

  final _DetailTab active;
  final ValueChanged<_DetailTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tabs = {
      _DetailTab.overview: l10n.videoDetailTabOverview,
      _DetailTab.versions: l10n.videoDetailTabVersions,
      _DetailTab.subtitles: l10n.videoDetailTabSubtitles,
    };
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MovieDetailTheme.border)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in tabs.entries)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelect(entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color:
                            active == entry.key
                                ? MovieDetailTheme.accent
                                : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    entry.value,
                    style: MovieDetailTheme.mono(
                      12,
                      color:
                          active == entry.key
                              ? MovieDetailTheme.foreground
                              : MovieDetailTheme.mutedText,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.item,
    required this.editMode,
    required this.overviewController,
  });

  final MovieVideoItem item;
  final bool editMode;
  final TextEditingController overviewController;

  @override
  Widget build(BuildContext context) {
    final overview = item.overview ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (editMode)
          TextField(
            controller: overviewController,
            maxLines: 5,
            cursorColor: MovieDetailTheme.accent,
            style: MovieDetailTheme.body(
              14,
              color: MovieDetailTheme.secondaryText,
              height: 1.6,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: MovieDetailTheme.surface,
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: MovieDetailTheme.accent.withValues(alpha: 0.30),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: MovieDetailTheme.accent.withValues(alpha: 0.30),
                ),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          )
        else if (overview.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 672),
            child: Text(
              overview,
              style: MovieDetailTheme.body(
                14,
                color: MovieDetailTheme.secondaryText,
                height: 1.6,
              ),
            ),
          ),
        if (item.castMembers.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text(
            'CAST',
            style: MovieDetailTheme.mono(
              AppTypography.bodySmall,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 800 ? 3 : 2;
              const gap = 12.0;
              final itemWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final member in item.castMembers)
                    SizedBox(
                      width: itemWidth,
                      child: Container(
                        padding: const EdgeInsets.only(left: 12),
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              width: 2,
                              color: MovieDetailTheme.border,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            _CastAvatar(
                              name: member.name,
                              profileUrl: member.profilePath,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MovieDetailTheme.body(
                                      14,
                                      color: MovieDetailTheme.foreground,
                                    ),
                                  ),
                                  if (member.character != null &&
                                      member.character!.isNotEmpty)
                                    Text(
                                      member.character!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: MovieDetailTheme.mono(
                                        AppTypography.bodySmall,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _VersionsTab extends ConsumerWidget {
  const _VersionsTab({required this.item});

  final MovieVideoItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final versionsAsync = ref.watch(movieVersionsProvider(item.id));
    return versionsAsync.when(
      loading:
          () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error:
          (error, _) => Text(
            movieErrorMessage(error),
            style: MovieDetailTheme.mono(AppTypography.bodySmall),
          ),
      data: (versions) {
        if (versions.isEmpty) {
          return Text(
            l10n.videoDetailNoVersions,
            style: MovieDetailTheme.mono(AppTypography.bodySmall),
          );
        }
        return Column(
          children: [
            for (final version in versions)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 1),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: MovieDetailTheme.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            version.versionLabel ?? 'Original',
                            style: MovieDetailTheme.body(
                              14,
                              color: MovieDetailTheme.foreground,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (version.videoCodec != null &&
                                  version.videoCodec!.trim().isNotEmpty)
                                version.videoCodec!.trim().toUpperCase(),
                              if (version.containerFormat != null &&
                                  version.containerFormat!.trim().isNotEmpty)
                                version.containerFormat!.trim().toLowerCase(),
                            ].join(' · '),
                            style: MovieDetailTheme.mono(
                              AppTypography.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (version.resolutionHeight != null &&
                        version.resolutionHeight! > 0)
                      Text(
                        '${version.resolutionHeight}p',
                        style: MovieDetailTheme.mono(
                          12,
                          color: MovieDetailTheme.accent,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SubtitlesTab extends ConsumerWidget {
  const _SubtitlesTab({
    required this.item,
    required this.uploading,
    required this.onUpload,
  });

  final MovieVideoItem item;
  final bool uploading;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tracksAsync = ref.watch(movieSubtitlesProvider(item.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: uploading ? null : onUpload,
              borderRadius: MovieRedesignPalette.borderRadius,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: MovieRedesignPalette.borderRadius,
                  border: Border.all(color: MovieDetailTheme.border),
                ),
                child: Text(
                  l10n.videoDetailUploadSubtitle,
                  style: MovieDetailTheme.mono(
                    12,
                    color:
                        uploading
                            ? MovieDetailTheme.mutedText
                            : MovieDetailTheme.secondaryText,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        tracksAsync.when(
          loading:
              () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          error:
              (error, _) => Text(
                movieErrorMessage(error),
                style: MovieDetailTheme.mono(AppTypography.bodySmall),
              ),
          data: (tracks) {
            if (tracks.isEmpty) {
              return Text(
                l10n.videoRedesignNoSubtitles,
                style: MovieDetailTheme.mono(AppTypography.bodySmall),
              );
            }
            return Column(
              children: [
                for (final track in tracks)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 1),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: MovieDetailTheme.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            track.label,
                            style: MovieDetailTheme.body(
                              14,
                              color: MovieDetailTheme.foreground,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          _formatOf(track.url) ?? '',
                          style: MovieDetailTheme.mono(AppTypography.bodySmall),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          track.embedded
                              ? l10n.videoRedesignSubtitleEmbedded
                              : l10n.videoRedesignSubtitleExternal,
                          style: MovieDetailTheme.mono(AppTypography.bodySmall),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  String? _formatOf(String? url) {
    if (url == null) {
      return null;
    }
    return RegExp(
      r'\.(vtt|srt|ass|ssa|ttml|sub)(?:\?|$)',
    ).firstMatch(url)?.group(1)?.toUpperCase();
  }
}

class _SubtitleLanguageDialog extends StatefulWidget {
  const _SubtitleLanguageDialog({required this.fileName});

  final String fileName;

  @override
  State<_SubtitleLanguageDialog> createState() =>
      _SubtitleLanguageDialogState();
}

class _SubtitleLanguageDialogState extends State<_SubtitleLanguageDialog> {
  String _language = 'zh';

  static const _languageOptions = [
    ('zh', '中文 Chinese'),
    ('en', 'English'),
    ('ja', '日本語 Japanese'),
    ('ko', '한국어 Korean'),
    ('und', 'Undetermined'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.movieDetailPalette;
    final l10n = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: MovieRedesignPalette.borderRadius,
        side: BorderSide(color: palette.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 384),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.fileName,
                style: MovieDetailTheme.mono(
                  AppTypography.bodySmall,
                  color: palette.foreground,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.videoRedesignLanguage,
                // ignore: font_size_whitelist
                style: MovieDetailTheme.mono(10),
              ),
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  borderRadius: MovieRedesignPalette.borderRadius,
                  border: Border.all(color: palette.border),
                  color: palette.muted,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _language,
                    isExpanded: true,
                    borderRadius: MovieRedesignPalette.borderRadius,
                    dropdownColor: palette.card,
                    items: [
                      for (final (value, label) in _languageOptions)
                        DropdownMenuItem(
                          value: value,
                          child: Text(
                            label,
                            style: MovieDetailTheme.mono(
                              AppTypography.bodySmall,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _language = value);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: palette.primary,
                  borderRadius: MovieRedesignPalette.borderRadius,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(_language),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Center(
                        child: Text(
                          l10n.videoRedesignConfirmUpload,
                          style: MovieDetailTheme.body(
                            14,
                            weight: FontWeight.w500,
                            color: palette.onPrimary,
                          ),
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
    );
  }
}

/// CAST 头像：48px 圆形，刮削图缺失时回退姓名首字母。
class _CastAvatar extends StatelessWidget {
  const _CastAvatar({required this.name, this.profileUrl});

  final String name;
  final String? profileUrl;

  @override
  Widget build(BuildContext context) {
    final url = profileUrl;
    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: MovieDetailTheme.surface,
      ),
      child:
          url != null && url.isNotEmpty
              ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: 96,
                errorWidget:
                    (context, error, stackTrace) => _CastInitials(name: name),
              )
              : _CastInitials(name: name),
    );
  }
}

class _CastInitials extends StatelessWidget {
  const _CastInitials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return Center(
      child: Text(
        initial,
        style: MovieDetailTheme.mono(
          AppTypography.titleMedium,
          color: MovieDetailTheme.accent,
        ),
      ),
    );
  }
}
