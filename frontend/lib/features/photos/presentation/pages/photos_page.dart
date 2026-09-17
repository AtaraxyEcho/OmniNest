import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/errors/user_facing_error_l10n.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/core/widgets/file_purge_confirmation.dart';
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
import 'package:omninest/features/photos/presentation/widgets/frame_dialogs.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_trash_view.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_top_bar.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_view_meta.dart';
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
    // Derive breakpoint booleans from width; the tree only switches form
    // across breakpoints, while content responds to constraints itself.
    final width = MediaQuery.sizeOf(context).width;
    final isWide = !hosted && !ResponsiveBreakpoints.isCompact(width);
    final sidebarCollapsed = width < 1024;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final photoState =
            ref.read(photoCenterControllerProvider).asData?.value;
        final controller = ref.read(photoCenterControllerProvider.notifier);
        if (photoState == null) {
          context.go('/portal');
          return;
        }
        // 返回优先级：退出多选 → 回图库视图 → 清空搜索 → 回门户。
        if (photoState.isSelectionMode) {
          controller.toggleSelectionMode();
          return;
        }
        if (photoState.frameView != FrameView.grid) {
          controller.setFrameView(FrameView.grid);
          return;
        }
        if (photoState.searchQuery.isNotEmpty) {
          controller.setSearchQuery('');
          return;
        }
        context.go('/portal');
      },
      child: Scaffold(
        backgroundColor: hosted ? Colors.transparent : context.frameColors.bg,
        body: ColoredBox(
          color: hosted ? Colors.transparent : context.frameColors.bg,
          child:
              isWide
                  ? _buildWideLayout(
                    stateAsync,
                    sidebarCollapsed: sidebarCollapsed,
                  )
                  : _buildNarrowLayout(stateAsync, hosted: hosted),
        ),
      ),
    );
  }

  /// 桌面宽屏布局：Frame 侧栏 + 顶栏 + 视图内容，宽 1024 以下侧栏折叠。
  Widget _buildWideLayout(
    AsyncValue<PhotoCenterState> stateAsync, {
    required bool sidebarCollapsed,
  }) {
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
                    collapsed: sidebarCollapsed,
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
            message: AppLocalizations.of(
              context,
            ).localizeUserFacing(describeUserFacingError(error)),
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
          // 极简托管布局：顶栏与底栏由壳层唯一提供，模块只渲染
          // 页内搜索条（壳层搜索钮展开）、视图页签行与内容、批量条。
          return Column(
            children: [
              _PhotosHostedSearchBar(
                searchController: _searchController,
                onSearchChanged: notifier.setSearchQuery,
              ),
              if (!data.isSelectionMode)
                _PhotosViewTabBar(
                  activeView: data.frameView,
                  onSelectView: notifier.setFrameView,
                ),
              Expanded(child: content),
              if (data.isSelectionMode && data.selectedPhotoIds.isNotEmpty)
                _buildAnimatedBatchBar(data),
            ],
          );
        }
        return Column(
          children: [
            FrameTopBar(
              view: data.frameView,
              searchController: _searchController,
              onSearchChanged: notifier.setSearchQuery,
              showTitle: false,
              searchExpanded: true,
              showBack: true,
              showImport: !data.isSelectionMode,
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
            message: AppLocalizations.of(
              context,
            ).localizeUserFacing(describeUserFacingError(error)),
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
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).localizeUserFacing(describeUserFacingError(error)),
          ),
        ),
      );
    }
  }

  /// 永久删除回收站中的照片。
  Future<void> _purgeFromTrash(PhotoItem photo) async {
    try {
      final deleted = await confirmAndRunFilePurge(
        context,
        resourceName: photo.title,
        action: (cascade) async {
          await ref
              .read(photoCenterControllerProvider.notifier)
              .purgePhotoFromTrash(photo.id, cascade: cascade);
        },
      );
      if (!deleted || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).photosTrashPurged)),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).localizeUserFacing(describeUserFacingError(error)),
          ),
        ),
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
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).localizeUserFacing(describeUserFacingError(error)),
          ),
        ),
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
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).localizeUserFacing(describeUserFacingError(error)),
          ),
        ),
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
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFrameConfirmDialog(
      context,
      title: l10n.photosDeleteAlbumTitle,
      body: l10n.photosDeleteAlbumConfirm(album.name),
      confirmLabel: l10n.photosDelete,
      destructive: true,
    );
    if (confirmed && context.mounted) {
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

  Future<void> _showCreateAlbumDialog(BuildContext context) async {
    final created = await showFrameNewAlbumDialog(context);
    if (created == null || !context.mounted) return;
    final (name, description) = created;
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .createAlbum(name: name, description: description);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).photosAlbumCreated(name),
            ),
          ),
        );
      }
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).photosCreateFailed),
          ),
        );
      }
    }
  }
}

/// 托管态页内搜索条：壳层顶栏搜索钮展开，承载模块内照片搜索。
class _PhotosHostedSearchBar extends ConsumerStatefulWidget {
  const _PhotosHostedSearchBar({
    required this.searchController,
    required this.onSearchChanged,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  @override
  ConsumerState<_PhotosHostedSearchBar> createState() =>
      _PhotosHostedSearchBarState();
}

class _PhotosHostedSearchBarState
    extends ConsumerState<_PhotosHostedSearchBar> {
  @override
  Widget build(BuildContext context) {
    final active = ref.watch(
      mobileModuleSearchActiveProvider(MobileModuleSearchHosts.photos),
    );
    if (!active) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final colors = context.frameColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.navBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.searchController,
              onChanged: widget.onSearchChanged,
              autofocus: true,
              style: TextStyle(
                fontSize: AppTypography.bodyLarge,
                color: colors.ink,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: colors.card,
                hintText: l10n.photosSearchHint,
                hintStyle: TextStyle(color: colors.muted),
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).coreClose,
            onPressed: () {
              ref
                  .read(
                    mobileModuleSearchActiveProvider(
                      MobileModuleSearchHosts.photos,
                    ).notifier,
                  )
                  .set(false);
              widget.searchController.clear();
              widget.onSearchChanged('');
            },
            icon: Icon(Icons.close_rounded, color: colors.muted),
          ),
        ],
      ),
    );
  }
}

/// 托管态视图页签行：五个主视图 + 收藏/回收站入口 + 导入。
class _PhotosViewTabBar extends StatelessWidget {
  const _PhotosViewTabBar({
    required this.activeView,
    required this.onSelectView,
  });

  final FrameView activeView;
  final ValueChanged<FrameView> onSelectView;

  static const List<FrameView> _views = [
    FrameView.grid,
    FrameView.timeline,
    FrameView.locations,
    FrameView.tags,
    FrameView.albums,
    FrameView.favorites,
    FrameView.trash,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.frameColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.navBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _views.length,
                separatorBuilder: (_, _) => const SizedBox(width: 2),
                itemBuilder: (context, index) {
                  final view = _views[index];
                  final selected = view == activeView;
                  return TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () => onSelectView(view),
                    child: Text(
                      frameViewLabel(l10n, view),
                      style: TextStyle(
                        fontSize: AppTypography.bodyMedium,
                        color: selected ? colors.accent : colors.muted,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  );
                },
              ),
            ),
            const FrameImportAction(),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
