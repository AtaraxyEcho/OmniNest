import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/errors/user_facing_error_l10n.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/animated_switcher_semantics.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/core/widgets/file_purge_confirmation.dart';
import 'package:omninest/core/widgets/mobile_segment_pager.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_sample_kit.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/domain/photo_timeline.dart';
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
import 'package:omninest/features/photos/presentation/widgets/photo_hosted_chrome.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_timeline_view.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

part 'photos_page_batch_actions.dart';
part 'photos_page_view_content.dart';

/// 照片中心主页：Frame 风格导航壳（侧栏/顶栏/底部导航）+ 六视图内容。
class PhotosPage extends ConsumerStatefulWidget {
  const PhotosPage({super.key});

  @override
  ConsumerState<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends ConsumerState<PhotosPage> {
  /// 离开照片模块：优先返回上一路由（Library/Home 推入栈），直达链接
  /// 作为栈底时回到媒体库空间。必须用 Navigator.pop 直弹：页面被
  /// PopScope(canPop: false) 拦截，maybePop 会反复回落到本回调形成
  /// 同步无限递归（真机表现为无响应后退出）。
  void _leavePhotos(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      context.go('/library');
    }
  }

  /// hosted 模块页返回：多选 → 回首栏（全部）→ 清搜索 → 离开模块；
  /// 头部返回钮与系统返回共用同一入口。
  void _handleHostedBack(BuildContext context) {
    final photoState = ref.read(photoCenterControllerProvider).asData?.value;
    final controller = ref.read(photoCenterControllerProvider.notifier);
    if (photoState?.isSelectionMode == true) {
      controller.toggleSelectionMode();
      return;
    }
    if (photoState != null && photoState.frameView != FrameView.grid) {
      controller.setFrameView(FrameView.grid);
      return;
    }
    if (photoState != null && photoState.searchQuery.isNotEmpty) {
      controller.setSearchQuery('');
      return;
    }
    _leavePhotos(context);
  }

  final TextEditingController _searchController = TextEditingController();
  bool _hostedViewResetApplied = false;
  VoidCallback? _routeListener;
  GoRouter? _router;
  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 样例模块页进入即定位第一栏（全部）：每次新挂载重置视图态，
    // 避免上次离开的分栏（时间线/影集…）在重进时残留。
    if (_hostedViewResetApplied) {
      return;
    }
    _hostedViewResetApplied = true;
    if (!MobileShellScope.isHosted(context)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final controller = ref.read(photoCenterControllerProvider.notifier);
      final current = ref.read(photoCenterControllerProvider).asData?.value;
      if (current == null) {
        return;
      }
      if (current.frameView != FrameView.grid) {
        controller.setFrameView(FrameView.grid);
      }
      if (current.isSelectionMode) {
        controller.toggleSelectionMode();
      }
    });
  }

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
          _leavePhotos(context);
          return;
        }
        // 托管模块页是根级叠加层：系统返回直接 pop 回来源空间。
        if (MobileShellScope.isHosted(context)) {
          _handleHostedBack(context);
          return;
        }
        // 返回优先级：退出多选 → 回图库视图 → 清空搜索 → 离开照片模块。
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
        _leavePhotos(context);
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
                                ref
                                        .watch(userCapabilitiesProvider)
                                        .canManageOwnActivity
                                    ? (photo) =>
                                        unawaited(_toggleFavorite(photo))
                                    : null,
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
      loading: () => const AppLoading(),
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
        final l10n = AppLocalizations.of(context);
        Widget contentFor(FrameView view) => _FrameViewContent(
          state: data.copyWith(frameView: view),
          compact: true,
          onOpenPhoto: (photo) => context.push('/photos/${photo.id}'),
          onOpenAlbum: (album) => context.push('/photos/albums/${album.id}'),
          onDeleteAlbum: (album) => _confirmDeleteAlbum(context, album),
          onCreateAlbum: () => _showCreateAlbumDialog(context),
          onToggleFavorite:
              ref.watch(userCapabilitiesProvider).canManageOwnActivity
                  ? (photo) => unawaited(_toggleFavorite(photo))
                  : null,
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
          // 托管模块页（样例 module-overlay）：深玻璃表面 + 玻璃横幅 +
          // 页内搜索条（横幅搜索钮展开）+ 视图页签行与内容、批量条。
          return MobilePageSurface(
            exposeBackdrop: true,
            backdropOpacity: 0.92,
            child: Column(
              children: [
                MobileModuleHeader(
                  title: l10n.modulePhotosTitle,
                  // 副标题读服务端总数：只列首屏 50 张时用已加载长度计数，
                  // 超过首屏就永远停在 50。
                  subtitle: l10n.photosModuleSubtitle(
                    data.photoTotalElements,
                    data.dashboard.totalAlbums,
                  ),
                  // 头部返回钮 = 直接离开模块回媒体库；逐级回退（多选→
                  // 图库→清搜索）只留给系统返回，见 PopScope 分支。
                  onBack: () => _leavePhotos(context),
                  actions: [
                    MobileGlassIconButton(
                      tooltip: l10n.photosSearchHint,
                      icon: Icons.search_rounded,
                      // 搜索统一进全局覆盖层并预选相册档：相册档走服务端
                      // 关键词，覆盖面比页内条更广。
                      onPressed:
                          () => unawaited(context.push('/search?scope=photo')),
                    ),
                  ],
                ),
                if (!data.isSelectionMode)
                  _PhotosViewTabBar(
                    activeView: data.frameView,
                    onSelectView: notifier.setFrameView,
                  ),
                Expanded(
                  // Tags 只保留在桌面/非托管：视图不在托管六段次序里时没有邻位
                  // 内容可画，分页会把它画成首段，所以这种视图不横滑——与旧检测器
                  // adjacentSection 返回 null 的口径一致。
                  child:
                      _PhotosViewTabBar.hostedViews.contains(data.frameView)
                          ? MobileSegmentPager<FrameView>(
                            sections: _PhotosViewTabBar.hostedViews,
                            current: data.frameView,
                            // 选择模式下页签行已隐藏，多选进行中一次误划就悄悄换掉
                            // 视图，用户无从察觉换到了哪。关掉横滑只换分页物理：
                            // 页内纵向滚动与滚动位置都不受影响，退出后跟手立刻回来。
                            interactionEnabled: !data.isSelectionMode,
                            onChanged: notifier.setFrameView,
                            pageBuilder: (context, view) => contentFor(view),
                          )
                          : contentFor(data.frameView),
                ),
                if (data.isSelectionMode && data.selectedPhotoIds.isNotEmpty)
                  _buildAnimatedBatchBar(data),
              ],
            ),
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
            Expanded(child: contentFor(data.frameView)),
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
                  // 整页首屏只留一处动画指示：此前是两块占位各塞一个转圈。
                  ? const AppLoading()
                  : const AppLoading(),
    );
  }

  /// 从回收站恢复照片。
  Future<void> _restoreFromTrash(PhotoItem photo) async {
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .restorePhotoFromTrash(photo.id);
      if (!mounted) return;
      showOmniFeedback(
        context,
        AppLocalizations.of(context).photosTrashRestored,
        severity: OmniFeedbackSeverity.success,
      );
    } on Exception catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        AppLocalizations.of(
          context,
        ).localizeUserFacing(describeUserFacingError(error)),
        severity: OmniFeedbackSeverity.error,
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
      showOmniFeedback(context, AppLocalizations.of(context).photosTrashPurged);
    } on Exception catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        AppLocalizations.of(
          context,
        ).localizeUserFacing(describeUserFacingError(error)),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  /// 清空回收站。
  Future<void> _purgeTrashWithFeedback() async {
    try {
      await ref.read(photoCenterControllerProvider.notifier).purgeTrash();
      if (!mounted) return;
      showOmniFeedback(context, AppLocalizations.of(context).photosTrashPurged);
    } on Exception catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        AppLocalizations.of(
          context,
        ).localizeUserFacing(describeUserFacingError(error)),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  /// 卡片心形切换收藏；失败时给出用户可读提示。
  Future<void> _toggleFavorite(PhotoItem photo) async {
    final wasFavorite = photo.favorite;
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .toggleFavorite(photo.id, currentFavorite: photo.favorite);
      if (!mounted) return;
      showOmniFeedback(
        context,
        wasFavorite
            ? AppLocalizations.of(context).favoriteRemoved
            : AppLocalizations.of(context).favoriteAdded,
        severity: OmniFeedbackSeverity.success,
      );
    } on Exception catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        AppLocalizations.of(
          context,
        ).localizeUserFacing(describeUserFacingError(error)),
        severity: OmniFeedbackSeverity.error,
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
          showOmniFeedback(
            context,
            AppLocalizations.of(context).photosDeletedAlbum(album.name),
            severity: OmniFeedbackSeverity.success,
          );
        }
      } on Exception {
        if (context.mounted) {
          showOmniFeedback(
            context,
            AppLocalizations.of(context).photosDeleteFailed,
            severity: OmniFeedbackSeverity.error,
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
        // 先清掉在播提示再弹出：同名相册连续创建时两条同文案 SnackBar
        // 并存会触发 SnackBar Hero tag 重复断言。
        showOmniFeedback(
          context,
          AppLocalizations.of(context).photosAlbumCreated(name),
          severity: OmniFeedbackSeverity.success,
        );
      }
    } on Exception {
      if (context.mounted) {
        showOmniFeedback(
          context,
          AppLocalizations.of(context).photosCreateFailed,
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
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

  /// 托管移动页签对齐样例六段（Library/Albums/Favorites/Timeline/Places/
  /// Trash）；Tags 仅桌面/非托管保留。
  static const List<FrameView> hostedViews = [
    FrameView.grid,
    FrameView.albums,
    FrameView.favorites,
    FrameView.timeline,
    FrameView.locations,
    FrameView.trash,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hosted = MobileShellScope.isHosted(context);
    final views = hosted ? hostedViews : _views;
    // 托管模块页：样例玻璃胶囊分段（无导入钮，与影视/音乐页签行同距）；
    // 非托管保持 Frame 页签行。
    if (hosted) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: MobileSegmentedControl<FrameView>(
            values: views,
            selected: views.contains(activeView) ? activeView : views.first,
            labelBuilder: (view) => frameViewLabel(l10n, view),
            onSelected: onSelectView,
            // 样例六段在 390 宽放不下（实测 431dp 对 350dp 内容带），
            // 这里按等分档让六段全部可见，而不是照样例横向滚动。
            shrinkToFit: true,
          ),
        ),
      );
    }
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
                itemCount: views.length,
                separatorBuilder: (_, _) => const SizedBox(width: 2),
                itemBuilder: (context, index) {
                  final view = views[index];
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
