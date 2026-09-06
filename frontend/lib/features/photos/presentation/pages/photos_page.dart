import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/presentation/widgets/batch_progress_dialog.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_albums_view.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_bottom_nav.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_locations_view.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_masonry_grid.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_sidebar.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_tags_view.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_trash_view.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_top_bar.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_common_widgets.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_timeline_view.dart';

part 'photos_page_batch_actions.dart';
part 'photos_page_view_content.dart';

/// 照片中心主页：Frame 风格导航壳（侧栏/顶栏/底部导航）+ 六视图内容。
class PhotosPage extends ConsumerStatefulWidget {
  const PhotosPage({super.key});

  @override
  ConsumerState<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends ConsumerState<PhotosPage> {
  final TextEditingController _searchController = TextEditingController();
  VoidCallback? _routeListener;
  GoRouter? _router;
  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final router = GoRouter.of(context);
      _router = router;
      void listener() {
        final path = router.routeInformationProvider.value.uri.path;
        if (path == '/photos' && mounted) {
          final now = DateTime.now();
          if (now.difference(_lastRefresh).inMilliseconds > 500) {
            _lastRefresh = now;
            ref.read(photoCenterControllerProvider.notifier).refresh();
          }
        }
      }

      _routeListener = listener;
      router.routeInformationProvider.addListener(listener);
    });
  }

  @override
  void dispose() {
    if (_routeListener != null && _router != null) {
      _router!.routeInformationProvider.removeListener(_routeListener!);
    }
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hosted = MobileShellScope.isHosted(context);
    final stateAsync = ref.watch(photoCenterControllerProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide =
            !hosted && !ResponsiveBreakpoints.isCompact(constraints.maxWidth);
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            context.go('/portal');
          },
          child: Scaffold(
            backgroundColor:
                hosted ? Colors.transparent : context.frameColors.bg,
            body: ColoredBox(
              color: hosted ? Colors.transparent : context.frameColors.bg,
              child:
                  isWide
                      ? _buildWideLayout(stateAsync, constraints.maxWidth)
                      : _buildNarrowLayout(stateAsync, hosted: hosted),
            ),
          ),
        );
      },
    );
  }

  /// 桌面宽屏布局：Frame 侧栏 + 顶栏 + 视图内容，宽 1024 以下侧栏折叠。
  Widget _buildWideLayout(
    AsyncValue<PhotoCenterState> stateAsync,
    double width,
  ) {
    return stateAsync.when(
      data: (data) {
        final notifier = ref.read(photoCenterControllerProvider.notifier);
        return Column(
          children: [
            // 顶栏贯穿侧边栏，通知/头像/返回入口与其他模块保持同一位置。
            FrameTopBar(
              view: data.frameView,
              searchController: _searchController,
              onSearchChanged: notifier.setSearchQuery,
              showTitle: true,
              showBack: true,
            ),
            Expanded(
              child: Row(
                children: [
                  FrameSidebar(
                    activeView: data.frameView,
                    onSelectView: notifier.setFrameView,
                    photoCount: data.visiblePhotoTotalElements,
                    albumCount: data.albums.length,
                    trashCount: data.dashboard.trashCount,
                    collapsed: width < 1024,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: _FrameViewContent(
                            state: data,
                            compact: false,
                            onOpenPhoto:
                                (photo) => context.push('/photos/${photo.id}'),
                            onOpenAlbum:
                                (album) =>
                                    context.push('/photos/albums/${album.id}'),
                            onDeleteAlbum:
                                (album) => _confirmDeleteAlbum(context, album),
                            onCreateAlbum:
                                () => _showCreateAlbumDialog(context),
                            onToggleFavorite:
                                (photo) => unawaited(_toggleFavorite(photo)),
                            onRestoreFromTrash:
                                (photo) => unawaited(_restoreFromTrash(photo)),
                            onDeleteForeverFromTrash:
                                (photo) => unawaited(_purgeFromTrash(photo)),
                            onEmptyTrash:
                                () => unawaited(_purgeTrashWithFeedback()),
                          ),
                        ),
                        if (data.isSelectionMode &&
                            data.selectedPhotoIds.isNotEmpty)
                          _buildAnimatedBatchBar(data),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      error:
          (error, stackTrace) => AppErrorView(
            message: describeUserFacingError(error).displayMessage,
            onRetry: () => ref.invalidate(photoCenterControllerProvider),
          ),
      loading: () => const AppLoading.grid(),
    );
  }

  /// 紧凑布局：非托管时含 Frame 顶栏，托管时由应用壳提供顶部导航。
  Widget _buildNarrowLayout(
    AsyncValue<PhotoCenterState> stateAsync, {
    required bool hosted,
  }) {
    return stateAsync.when(
      data: (data) {
        final notifier = ref.read(photoCenterControllerProvider.notifier);
        final content = _FrameViewContent(
          state: data,
          compact: true,
          onOpenPhoto: (photo) => context.push('/photos/${photo.id}'),
          onOpenAlbum: (album) => context.push('/photos/albums/${album.id}'),
          onDeleteAlbum: (album) => _confirmDeleteAlbum(context, album),
          onCreateAlbum: () => _showCreateAlbumDialog(context),
          onToggleFavorite: (photo) => unawaited(_toggleFavorite(photo)),
          onRestoreFromTrash: (photo) => unawaited(_restoreFromTrash(photo)),
          onDeleteForeverFromTrash:
              (photo) => unawaited(_purgeFromTrash(photo)),
          onEmptyTrash: () => unawaited(_purgeTrashWithFeedback()),
        );
        final bottomNav =
            data.isSelectionMode
                ? null
                : FrameBottomNav(
                  activeView: data.frameView,
                  onSelectView: notifier.setFrameView,
                  useSafeArea: !hosted,
                );
        if (hosted) {
          // 应用壳托管时同样按设计稿移动端结构渲染：顶栏 + 内容 + 底部导航。
          return Column(
            children: [
              FrameTopBar(
                view: data.frameView,
                searchController: _searchController,
                onSearchChanged: notifier.setSearchQuery,
                showTitle: false,
                searchExpanded: true,
              ),
              Expanded(child: content),
              if (bottomNav != null) bottomNav,
              if (data.isSelectionMode && data.selectedPhotoIds.isNotEmpty)
                _buildAnimatedBatchBar(data),
            ],
          );
        }
        return Column(
          children: [
            SafeArea(
              bottom: false,
              child: FrameTopBar(
                view: data.frameView,
                searchController: _searchController,
                onSearchChanged: notifier.setSearchQuery,
                showTitle: false,
                searchExpanded: true,
                showBack: true,
              ),
            ),
            Expanded(child: content),
            if (bottomNav != null) bottomNav,
            if (data.isSelectionMode && data.selectedPhotoIds.isNotEmpty)
              _buildAnimatedBatchBar(data),
          ],
        );
      },
      error:
          (error, stackTrace) => AppErrorView(
            message: describeUserFacingError(error).displayMessage,
            onRetry: () => ref.invalidate(photoCenterControllerProvider),
          ),
      loading:
          () =>
              hosted
                  ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        MobileSkeletonBlock(height: 220),
                        SizedBox(height: 16),
                        MobileSkeletonBlock(height: 180),
                      ],
                    ),
                  )
                  : const AppLoading.grid(),
    );
  }

  /// 从回收站恢复照片。
  Future<void> _restoreFromTrash(PhotoItem photo) async {
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .restorePhotoFromTrash(photo.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).photosTrashRestored),
        ),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeUserFacingError(error).displayMessage)),
      );
    }
  }

  /// 永久删除回收站中的照片。
  Future<void> _purgeFromTrash(PhotoItem photo) async {
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .purgePhotoFromTrash(photo.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).photosTrashPurged)),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeUserFacingError(error).displayMessage)),
      );
    }
  }

  /// 清空回收站。
  Future<void> _purgeTrashWithFeedback() async {
    try {
      await ref.read(photoCenterControllerProvider.notifier).purgeTrash();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).photosTrashPurged)),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeUserFacingError(error).displayMessage)),
      );
    }
  }

  /// 卡片心形切换收藏；失败时给出用户可读提示。
  Future<void> _toggleFavorite(PhotoItem photo) async {
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .toggleFavorite(photo.id, currentFavorite: photo.favorite);
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeUserFacingError(error).displayMessage)),
      );
    }
  }

  /// 多选操作条入场：自底部滑入并渐显。
  Widget _buildAnimatedBatchBar(PhotoCenterState state) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder:
          (context, t, child) => Transform.translate(
            offset: Offset(0, t * 72),
            child: Opacity(opacity: 1 - t, child: child),
          ),
      child: _BatchActionBar(state: state, ref: ref),
    );
  }

  Future<void> _confirmDeleteAlbum(
    BuildContext context,
    PhotoAlbum album,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: context.photosColors.surfaceContainerHigh,
            title: Text(
              AppLocalizations.of(context).photosDeleteAlbumTitle,
              style: TextStyle(color: context.photosColors.onSurface),
            ),
            content: Text(
              AppLocalizations.of(context).photosDeleteAlbumConfirm(album.name),
              style: TextStyle(color: context.photosColors.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.of(context).photosCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: context.photosColors.danger,
                ),
                child: Text(AppLocalizations.of(context).photosDelete),
              ),
            ],
          ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await ref
            .read(photoCenterControllerProvider.notifier)
            .deleteAlbum(album.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).photosDeletedAlbum(album.name),
              ),
            ),
          );
        }
      } on Exception {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).photosDeleteFailed),
            ),
          );
        }
      }
    }
  }

  void _showCreateAlbumDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (ctx) => PhotoDialogTextField(
            builder:
                (ctx, nameController) => PhotoDialogTextField(
                  builder:
                      (ctx, descController) => AlertDialog(
                        backgroundColor:
                            context.photosColors.surfaceContainerHigh,
                        title: Text(
                          AppLocalizations.of(context).photosNewAlbum,
                          style: TextStyle(
                            color: context.photosColors.onSurface,
                          ),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: nameController,
                              autofocus: true,
                              style: TextStyle(
                                color: context.photosColors.onSurface,
                              ),
                              decoration: InputDecoration(
                                labelText:
                                    AppLocalizations.of(
                                      context,
                                    ).photosAlbumName,
                                hintText:
                                    AppLocalizations.of(
                                      context,
                                    ).photosAlbumNameHint,
                              ),
                            ),
                            SizedBox(height: 12),
                            TextField(
                              controller: descController,
                              style: TextStyle(
                                color: context.photosColors.onSurface,
                              ),
                              decoration: InputDecoration(
                                labelText:
                                    AppLocalizations.of(
                                      context,
                                    ).photosAlbumDescription,
                                hintText:
                                    AppLocalizations.of(
                                      context,
                                    ).photosAlbumDescriptionHint,
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              AppLocalizations.of(context).photosCancel,
                            ),
                          ),
                          FilledButton(
                            onPressed: () async {
                              final name = nameController.text.trim();
                              if (name.isEmpty) return;
                              Navigator.pop(ctx);
                              try {
                                await ref
                                    .read(
                                      photoCenterControllerProvider.notifier,
                                    )
                                    .createAlbum(
                                      name: name,
                                      description: descController.text.trim(),
                                    );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppLocalizations.of(
                                          context,
                                        ).photosAlbumCreated(name),
                                      ),
                                    ),
                                  );
                                }
                              } on Exception {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppLocalizations.of(
                                          context,
                                        ).photosCreateFailed,
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            child: Text(
                              AppLocalizations.of(context).photosCreate,
                            ),
                          ),
                        ],
                      ),
                ),
          ),
    );
  }
}
