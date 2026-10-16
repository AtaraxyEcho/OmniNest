import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/app/theme/feature/music_chrome_colors.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_segment_pager.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/workstation_portal_link.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_deck_search_controller.dart';
import 'package:omninest/features/music/application/music_deck_source_selection_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_content.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_layout.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_mini_player.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_models.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_navigation.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_queue_sheet.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_search.dart';
import 'package:omninest/features/music/presentation/widgets/music_platform_login.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_overlay.dart';
import 'package:omninest/features/music/presentation/player/music_playback_settings_dialog.dart';

/// 自适应 Music Deck 主界面。
class MusicDeckShell extends ConsumerStatefulWidget {
  const MusicDeckShell({super.key});

  @override
  ConsumerState<MusicDeckShell> createState() => _MusicDeckShellState();
}

class _MusicDeckShellState extends ConsumerState<MusicDeckShell> {
  /// 播放岛玻璃与中内容列之间的呼吸间隙，避免两块玻璃的 1px 描边相贴。
  static const double _islandGap = 12;

  /// 中内容列与搜索浮层的底距：控制岛高度加呼吸间隙
  /// （高度取自 MusicDeckMiniPlayer.barHeight，单一事实来源）。
  /// 左右两张侧卡不使用该底距，与播放岛共用窗口底部的同一条基线。
  static const double _playerOverlayInset =
      MusicDeckMiniPlayer.barHeight + _islandGap;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'Music Deck 搜索');
  Timer? _searchDismissTimer;
  MusicDeckSection _section = MusicDeckSection.home;
  MusicDeckLibraryView _libraryView = MusicDeckLibraryView.tracks;
  MusicDeckCollectionSelection? _collection;
  bool _searchFocused = false;
  bool _immersivePlayerVisible = false;

  @override
  void dispose() {
    _searchDismissTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 甲板树只用到「已启用且已连接」的平台状态：按 `statuses` 切片订阅，
    // 账号未变时歌单/曲目发布不再重建整棵树。派生放在 build 内做，因为
    // `select` 以 `==` 比较，每次派生的新列表都会被判为变化。
    final platformStatuses = ref.watch(
      musicPlatformLibraryProvider.select(
        (async) =>
            async.asData?.value.statuses ?? const <MusicPlatformStatus>[],
      ),
    );
    final platform = musicConnectedPlatformStatuses(platformStatuses);
    final sources = ref.watch(musicDeckSourceSelectionProvider);
    final width = MediaQuery.sizeOf(context).width;
    final compact = MobileShellScope.isHosted(context) || width < 760;
    return AnimatedSwitcher(
      duration: MotionToken.resolve(context, const Duration(milliseconds: 360)),
      reverseDuration: MotionToken.resolve(
        context,
        const Duration(milliseconds: 280),
      ),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder:
          (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 退场子树已被替换、正在淡出后销毁：其语义节点与入场子树在同一批
              // 更新中被移除，会让 Windows 辅助功能桥报 "will not be in the tree"。
              // 这里只排除正在销毁的旧子树，当前子树的语义不受影响。
              for (final child in previousChildren)
                ExcludeSemantics(child: child),
              if (currentChild != null) currentChild,
            ],
          ),
      transitionBuilder:
          (child, animation) => FadeTransition(
            opacity: animation,
            // 仅淡入：避免缩放时透明沉浸层露出底层白/浅色边。
            child: child,
          ),
      child:
          _immersivePlayerVisible
              ? MusicImmersiveOverlay(
                key: const ValueKey<String>('music-player-detail'),
                onClose: () => setState(() => _immersivePlayerVisible = false),
              )
              // 语义容器：阻断子树语义向页面根合并。此前禁用态的播放按钮
              // 语义沿无边界祖先链一路合并到语义树根，整页被标记为
              // [disabled] 按钮，屏幕阅读器完全不可用。
              : Semantics(
                container: true,
                explicitChildNodes: true,
                child: Focus(
                  key: const ValueKey<String>('music-deck-system'),
                  autofocus: true,
                  onKeyEvent: _handleKeyEvent,
                  child: BlockSemantics(
                    // Music 模块整页遮盖下层路由（门户）：把被遮盖内容的
                    // 语义整体排除，避免其数百节点随每次语义更新重新序列
                    // 化，触发 Windows 辅助功能桥 "will not be in the tree"
                    // 的更新失败。
                    child: PopScope(
                      // 歌单/专辑/艺人详情是页内层（`_collection`），不是路由：
                      // 打开着详情时一次侧滑应先收详情，而不是整块离开音乐模块。
                      // 分区页签不在此列——那里的「一次就出去」是既有裁定。
                      canPop: _collection == null,
                      onPopInvokedWithResult: (didPop, result) {
                        if (didPop) return;
                        _closeCollection();
                      },
                      child: Scaffold(
                        backgroundColor: Colors.transparent,
                        body:
                            compact
                                ? _buildMobile(context, platform, sources)
                                : _buildDesktop(context, platform, sources),
                      ),
                    ),
                  ),
                ),
              ),
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    List<MusicPlatformStatus> platform,
    Set<MusicPlatform> sources,
  ) {
    final width = MediaQuery.sizeOf(context).width;
    final layout = MusicDeckDesktopLayout.resolve(width);
    final user = ref.watch(authSessionProvider).asData?.value.user;
    // 本地管理扫描按 ownerUserId 过滤，成员可维护自己的曲库
    final canManage = user?.permissions.contains('media:write') ?? false;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          layout.horizontalPadding,
          16,
          layout.horizontalPadding,
          16,
        ),
        child: Stack(
          key: const ValueKey<String>('music-deck-desktop-layout'),
          children: [
            Column(
              children: [
                _buildDesktopTopBar(
                  context,
                  searchMaxWidth: layout.searchMaxWidth,
                  sources: sources,
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Row(
                    children: [
                      // 侧卡与播放岛同底线：不设底距，卡片下探到窗口底部基线。
                      MusicDeckNavigation(
                        selected: _section,
                        compact: layout.compactNavigation,
                        canManage: canManage,
                        connectedPlatformCount: platform.length,
                        onSelected: _selectSection,
                        onManageAccounts: _openAccounts,
                      ),
                      const SizedBox(width: MusicDeckDesktopLayout.cardGap),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            bottom: _playerOverlayInset,
                          ),
                          child: MusicDeckContent(
                            section: _section,
                            libraryView: _libraryView,
                            sources: sources,
                            collection: _collection,
                            onSectionChanged: _selectSection,
                            onLibraryViewChanged:
                                (view) => setState(() => _libraryView = view),
                            onOpenCollection: _openCollection,
                            onCloseCollection: _closeCollection,
                          ),
                        ),
                      ),
                      if (layout.showWidePanel) ...[
                        const SizedBox(width: MusicDeckDesktopLayout.cardGap),
                        SizedBox(
                          width: layout.widePanelWidth,
                          child: _WideNowPanel(platform: platform),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              left: layout.navigationWidth + 14,
              right: layout.trailingPanelSpace,
              top: 54,
              // 矮视口下搜索结果尾部会滑入底部播放条下方：约束底边
              // 止于播放条顶线，列表内部自行滚动。
              bottom: _playerOverlayInset,
              child: IgnorePointer(
                ignoring: !_searchFocused,
                child: AnimatedOpacity(
                  opacity: _searchFocused ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  // 透明度归零会整棵摘掉搜索结果的语义子树，重新聚焦时再整棵
                  // 加回：Windows 辅助功能桥会在仍持有旧节点 id 时更新失败
                  // （"will not be in the tree and is not the new root"）。
                  // 交互本身由外层 IgnorePointer 屏蔽，读屏可以继续停留在树上。
                  alwaysIncludeSemantics: true,
                  child: MusicDeckSearchOverlay(onDismiss: _closeSearch),
                ),
              ),
            ),
            // 播放岛取中内容列的整条水平带：与两张侧卡各留 cardGap，
            // 底边与侧卡落在同一条基线上；仅在超宽屏按上限收束居中。
            Positioned(
              left: layout.navigationWidth + MusicDeckDesktopLayout.cardGap,
              right: layout.trailingPanelSpace,
              bottom: 0,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: layout.playerMaxWidth),
                  child: MusicDeckMiniPlayer(
                    compact: false,
                    onOpenQueue: () => showMusicDeckQueue(context),
                    onOpenPlayer: _openImmersivePlayer,
                    onOpenImmersive: _openImmersivePlayer,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTopBar(
    BuildContext context, {
    required double searchMaxWidth,
    required Set<MusicPlatform> sources,
  }) {
    final l10n = AppLocalizations.of(context);
    final colors = context.musicColors;
    return SizedBox(
      height: AppControlTokens.fieldHeight,
      child: Row(
        children: [
          WorkstationPortalLink(
            onTap: () => context.go(modulePortalLinkTarget(context)),
          ),
          const SizedBox(width: 12),
          // 三端统一品牌入口：桌面顶栏以 logo 领起，与 Portal 顶栏同语言。
          const BrandLogo(size: 22, radius: 6),
          const SizedBox(width: 8),
          Text(
            'OmniNest',
            style: TextStyle(
              color: colors.onSurface,
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: searchMaxWidth),
              child: MusicDeckSearchField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                sources: sources,
                onChanged: _updateSearch,
                onFocusChanged: _setSearchFocused,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _SourceFilterButton(
            sources: sources,
            availableSources: _availableSources(),
            onToggle: _toggleSource,
          ),
          const Spacer(),
          _TopAction(
            tooltip: l10n.portalLocalBackdropTitle,
            icon: Icons.wallpaper_rounded,
            onPressed: _openBackdropSettings,
          ),
          _TopAction(
            tooltip: l10n.musicDeckManageAccounts,
            icon: Icons.cloud_sync_outlined,
            onPressed: _openAccounts,
          ),
          FontScaleControl(size: 20, color: colors.onSurface),
          NotificationIcon(size: 20, color: colors.onSurface),
          const SizedBox(width: 8),
          const UserAvatarMenu(),
        ],
      ),
    );
  }

  Widget _buildMobile(
    BuildContext context,
    List<MusicPlatformStatus> platform,
    Set<MusicPlatform> sources,
  ) {
    final l10n = AppLocalizations.of(context);
    final colors = context.musicColors;
    final hosted = MobileShellScope.isHosted(context);
    final center = ref.watch(musicCenterControllerProvider).asData?.value;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(hosted ? 20 : 12, 8, hosted ? 20 : 12, 8),
      child: Column(
        children: [
          if (hosted) ...[
            MobileModuleHeader(
              title: l10n.moduleMusicTitle,
              subtitle: l10n.musicModuleSubtitle(
                center?.tracks.length ?? 0,
                center?.albums.length ?? 0,
              ),
              onBack: () {
                // 头部返回钮与系统侧滑同一阶梯：详情层先收，再离开模块。
                if (_collection != null) {
                  _closeCollection();
                  return;
                }
                // 分区切换不是导航历史：早先「非首栏先回首页」要多按一次才出得去。
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop();
                } else {
                  context.go('/library');
                }
              },
              actions: [
                // 样例音乐头只有 返回 + 队列 两枚圆钮，队列即打开完整播放器
                // （稿子里那颗的 aria-label 就是「Open now playing」）。
                // 头部的搜索钮按样例撤下：全局搜索覆盖层仍从其它空间与
                // 影视/相册头部可达，这一档是本模块的刻意偏离。
                MobileGlassIconButton(
                  tooltip: l10n.musicDeckNowPlaying,
                  vector: OmniIcons.queue,
                  onPressed: _openImmersivePlayer,
                ),
              ],
            ),
          ],
          if (!hosted)
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  WorkstationPortalLink(
                    onTap: () => context.go(modulePortalLinkTarget(context)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _section.label(l10n),
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: AppTypography.titleLarge,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.musicSearch,
                    onPressed: _openMobileSearch,
                    icon: const Icon(Icons.search_rounded),
                  ),
                  // 移动端不提供音源筛选（筛选为桌面悬浮控件职责）；
                  // 仅保留平台账号管理，连接状态经徽标提示。
                  IconButton(
                    tooltip: l10n.musicDeckManageAccounts,
                    onPressed: _openAccounts,
                    icon: Badge(
                      isLabelVisible: platform.isNotEmpty,
                      child: const Icon(Icons.manage_accounts_rounded),
                    ),
                  ),
                ],
              ),
            ),
          if (!hosted) ...[const SizedBox(height: 8)],
          // 四段导航常驻（hosted 托管态同样直达，替代"仅 Home 内链接"）。
          Align(
            alignment: Alignment.centerLeft,
            child: MusicDeckMobileNavigation(
              selected: _section,
              onSelected: _selectSection,
            ),
          ),
          if (hosted) ...[
            const SizedBox(height: 14),
            const _MobileSourceBanner(),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: MobileSegmentPager<MusicDeckSection>(
              sections: MusicDeckMobileNavigation.mobileSections,
              current: _section,
              onChanged: _selectSection,
              pageBuilder:
                  (context, section) => MusicDeckContent(
                    section: section,
                    libraryView: _libraryView,
                    sources: sources,
                    // 歌单/收藏集详情只属于当前分段：邻居页拿到它会在预览里画出
                    // 另一段的详情视图。
                    collection: section == _section ? _collection : null,
                    onSectionChanged: _selectSection,
                    onLibraryViewChanged:
                        (view) => setState(() => _libraryView = view),
                    onOpenCollection: _openCollection,
                    onCloseCollection: _closeCollection,
                  ),
            ),
          ),
          if (!hosted) ...[
            MusicDeckMiniPlayer(
              compact: true,
              onOpenQueue: () => showMusicDeckQueue(context),
              onOpenPlayer: _openImmersivePlayer,
            ),
            const SizedBox(height: 7),
          ],
        ],
      ),
    );
    if (hosted) {
      // 平板宽度触屏内容按壳层 chrome 同宽封顶居中：卡片行/列表行
      // 不被整屏拉伸，与底栏 tab 组同语言；手机宽度无感直通。
      // 右下播放设置 FAB 悬浮在壳层迷你播放条上方（样例 music-settings-fab）。
      // 样例 module-overlay：深玻璃表面（≈.94 不透明）承载全模块。
      return MobilePageSurface(
        exposeBackdrop: true,
        backdropOpacity: 0.92,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: content,
              ),
            ),
            // 样例 music-settings-fab：模块页盖住壳层迷你条，FAB 贴内容底缘。
            Positioned(
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 18,
              child: _MobileSettingsFab(
                onPressed: () => showMusicPlaybackSettingsDialog(context, ref),
              ),
            ),
          ],
        ),
      );
    }
    return SafeArea(child: content);
  }

  List<MusicPlatform> _availableSources() {
    final statuses =
        ref
            .watch(musicPlatformLibraryProvider)
            .asData
            ?.value
            .connectedStatuses ??
        const <MusicPlatformStatus>[];
    return <MusicPlatform>[
      MusicPlatform.local,
      for (final status in statuses)
        MusicPlatform.fromApiValue(status.platform),
    ];
  }

  void _selectSection(MusicDeckSection section) {
    setState(() {
      _section = section;
      _collection = null;
    });
  }

  void _toggleSource(MusicPlatform source) {
    ref.read(musicDeckSourceSelectionProvider.notifier).toggle(source);
    _updateSearch(_searchController.text);
  }

  Future<void> _openCollection(MusicDeckCollectionSelection selection) async {
    setState(() => _collection = selection);
    switch (selection) {
      case LocalMusicDeckCollection(:final playlist):
        await ref
            .read(musicCenterControllerProvider.notifier)
            .openPlaylist(playlist);
      case OnlineMusicDeckCollection(:final playlist):
        await ref
            .read(musicPlatformLibraryProvider.notifier)
            .loadPlaylistTracks(playlist, forceRefresh: true);
      case DailyRecommendationMusicDeckCollection():
        break;
      case AlbumMusicDeckCollection(:final album):
        ref.read(musicCenterControllerProvider.notifier).openAlbum(album);
      case ArtistMusicDeckCollection(:final artist):
        ref.read(musicCenterControllerProvider.notifier).openArtist(artist);
      case OnlineAlbumMusicDeckCollection() ||
          OnlineArtistMusicDeckCollection():
        break;
    }
  }

  void _closeCollection() {
    final selection = _collection;
    setState(() => _collection = null);
    switch (selection) {
      case LocalMusicDeckCollection():
        ref.read(musicCenterControllerProvider.notifier).closePlaylist();
      case AlbumMusicDeckCollection():
        ref.read(musicCenterControllerProvider.notifier).closeAlbum();
      case ArtistMusicDeckCollection():
        ref.read(musicCenterControllerProvider.notifier).closeArtist();
      case OnlineMusicDeckCollection() ||
          DailyRecommendationMusicDeckCollection() ||
          OnlineAlbumMusicDeckCollection() ||
          OnlineArtistMusicDeckCollection() ||
          null:
        break;
    }
  }

  void _updateSearch(String query) {
    final sources = ref.read(musicDeckSourceSelectionProvider);
    ref.read(musicDeckSearchProvider.notifier).updateQuery(query, sources);
    if (query.trim().length >= 2 && !_searchFocused) {
      setState(() => _searchFocused = true);
    }
  }

  void _setSearchFocused(bool focused) {
    _searchDismissTimer?.cancel();
    if (focused) {
      setState(() => _searchFocused = true);
      return;
    }
    _searchDismissTimer = Timer(const Duration(milliseconds: 160), () {
      if (mounted && !_searchFocusNode.hasFocus) {
        setState(() => _searchFocused = false);
      }
    });
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(musicDeckSearchProvider.notifier).clear();
    setState(() => _searchFocused = false);
  }

  Future<void> _openAccounts() async {
    await PlatformLoginSheet.show(context);
    if (!mounted) {
      return;
    }
    // 关闭面板同样走完整刷新链（资料 + 曲库失效），覆盖断开平台等
    // 未走 QR 确认路径的账号变更。
    final musicController = ref.read(musicCenterControllerProvider.notifier);
    unawaited(musicController.refreshAfterPlatformChange());
  }

  Future<void> _openBackdropSettings() {
    return showAppBackdropSettings(context);
  }

  Future<void> _openMobileSearch() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => const MusicDeckMobileSearchPage(),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_immersivePlayerVisible) {
      setState(() => _immersivePlayerVisible = false);
      return KeyEventResult.handled;
    }
    if (_searchFocused) {
      _closeSearch();
      return KeyEventResult.handled;
    }
    if (_collection != null) {
      _closeCollection();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openImmersivePlayer() {
    if (MobileShellScope.isHosted(context)) {
      context.push('/music/now-playing');
      return;
    }
    if (_immersivePlayerVisible) {
      return;
    }
    setState(() => _immersivePlayerVisible = true);
  }
}

/// 来源状态横幅（样例 source-banner）：平台同步异常时提示本地曲库可用
/// 并给重试；有已连接平台时显示连接徽标；无平台数据时不渲染。
class _MobileSourceBanner extends ConsumerWidget {
  const _MobileSourceBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(musicPlatformLibraryProvider);
    if (async.hasError) {
      return MusicDeckGlass(
        opacity: 0.14,
        blur: 12,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(
              Icons.sync_problem_rounded,
              size: 15,
              color: MusicChromeColors.goldWarning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.musicSourceSyncError,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: AppTypography.labelSmall),
              ),
            ),
            TextButton(
              onPressed:
                  () => unawaited(
                    ref
                        .read(musicCenterControllerProvider.notifier)
                        .refreshAfterPlatformChange(),
                  ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      );
    }
    final connected =
        async.asData?.value.connectedStatuses ?? const <MusicPlatformStatus>[];
    if (connected.isEmpty) {
      return const SizedBox.shrink();
    }
    return MusicDeckGlass(
      opacity: 0.1,
      blur: 12,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_done_outlined,
            size: 14,
            color: MusicChromeColors.tealSoft,
          ),
          const SizedBox(width: 8),
          Text(
            l10n.musicDeckConnectedSources,
            style: TextStyle(
              fontSize: AppTypography.labelSmall,
              color: context.musicColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              children: [
                for (final status in connected)
                  MusicDeckSourceBadge(
                    platform: MusicPlatform.fromApiValue(status.platform),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 右下播放设置悬浮钮（样例 music-settings-fab）：打开睡眠定时/倍速/音质。
class _MobileSettingsFab extends StatelessWidget {
  const _MobileSettingsFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox.square(
      dimension: 46,
      child: Tooltip(
        message: l10n.musicPlaybackSettings,
        child: IconButton(
          onPressed: onPressed,
          icon: const Icon(Icons.equalizer_rounded, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: MusicChromeColors.panelBackground,
            foregroundColor: MusicChromeColors.nearWhite,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          ),
        ),
      ),
    );
  }
}

class _SourceFilterButton extends StatelessWidget {
  const _SourceFilterButton({
    required this.sources,
    required this.availableSources,
    required this.onToggle,
  });

  final Set<MusicPlatform> sources;
  final List<MusicPlatform> availableSources;
  final ValueChanged<MusicPlatform> onToggle;

  @override
  Widget build(BuildContext context) {
    return MusicDeckGlass(
      opacity: 0.2,
      blur: 12,
      child: PopupMenuButton<MusicPlatform>(
        tooltip: AppLocalizations.of(context).musicDeckSources,
        onSelected: onToggle,
        itemBuilder:
            (context) => availableSources
                .map(
                  (source) => CheckedPopupMenuItem<MusicPlatform>(
                    value: source,
                    checked: sources.contains(source),
                    child: MusicDeckSourceBadge(platform: source),
                  ),
                )
                .toList(growable: false),
        child: SizedBox(
          height: 42,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tune_rounded, size: 18),
                const SizedBox(width: 7),
                Text(
                  AppLocalizations.of(context).musicDeckSources,
                  style: const TextStyle(fontSize: AppTypography.bodySmall),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopAction extends StatelessWidget {
  const _TopAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: context.musicColors.onSurface, size: 19),
    );
  }
}

class _WideNowPanel extends ConsumerWidget {
  const _WideNowPanel({required this.platform});

  final List<MusicPlatformStatus> platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.musicColors;
    final center = ref.watch(musicCenterControllerProvider).asData?.value;
    final track = center?.activeTrack;
    final statuses = platform;
    return MusicDeckGlass(
      opacity: 0.16,
      blur: 10,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).musicDeckNowPlaying,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: AppTypography.bodyLarge,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 1,
            child: MusicDeckArtwork(
              title: track?.title ?? '',
              imageUrl: track?.coverUrl,
            ),
          ),
          const SizedBox(height: 13),
          Text(
            track?.title ?? AppLocalizations.of(context).musicNotPlaying,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: AppTypography.bodyLarge,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            track?.artistName ??
                AppLocalizations.of(context).musicDeckSelectTrack,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: AppTypography.labelSmall,
            ),
          ),
          const Spacer(),
          Text(
            AppLocalizations.of(context).musicDeckConnectedSources,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: AppTypography.labelSmall,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              const MusicDeckSourceBadge(platform: MusicPlatform.local),
              for (final status in statuses)
                MusicDeckSourceBadge(
                  platform: MusicPlatform.fromApiValue(status.platform),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
