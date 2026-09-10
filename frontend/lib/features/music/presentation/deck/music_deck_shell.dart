import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
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

/// 自适应 Music Deck 主界面。
class MusicDeckShell extends ConsumerStatefulWidget {
  const MusicDeckShell({super.key});

  @override
  ConsumerState<MusicDeckShell> createState() => _MusicDeckShellState();
}

class _MusicDeckShellState extends ConsumerState<MusicDeckShell> {
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
    final platform = ref.watch(musicPlatformLibraryProvider).asData?.value;
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
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
      transitionBuilder:
          (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
              child: child,
            ),
          ),
      child:
          _immersivePlayerVisible
              ? MusicImmersiveOverlay(
                key: const ValueKey<String>('music-player-detail'),
                onClose: () => setState(() => _immersivePlayerVisible = false),
              )
              : Focus(
                key: const ValueKey<String>('music-deck-system'),
                autofocus: true,
                onKeyEvent: _handleKeyEvent,
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  body:
                      compact
                          ? _buildMobile(context, platform, sources)
                          : _buildDesktop(context, platform, sources),
                ),
              ),
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    MusicPlatformLibraryState? platform,
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
                      MusicDeckNavigation(
                        selected: _section,
                        compact: layout.compactNavigation,
                        canManage: canManage,
                        connectedPlatformCount:
                            platform?.connectedStatuses.length ?? 0,
                        onSelected: _selectSection,
                        onManageAccounts: _openAccounts,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 88),
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
                        const SizedBox(width: 14),
                        SizedBox(
                          width: layout.widePanelWidth,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 88),
                            child: _WideNowPanel(platform: platform),
                          ),
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
              child: IgnorePointer(
                ignoring: !_searchFocused,
                child: AnimatedOpacity(
                  opacity: _searchFocused ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: MusicDeckSearchOverlay(onDismiss: _closeSearch),
                ),
              ),
            ),
            Positioned(
              left: layout.navigationWidth + 34,
              right: layout.trailingPanelSpace + 20,
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
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => context.go('/portal'),
            icon: Icon(Icons.arrow_back_rounded, color: colors.onSurface),
          ),
          const SizedBox(width: 6),
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
    MusicPlatformLibraryState? platform,
    Set<MusicPlatform> sources,
  ) {
    final l10n = AppLocalizations.of(context);
    final colors = context.musicColors;
    final hosted = MobileShellScope.isHosted(context);
    final content = Padding(
      padding: EdgeInsets.fromLTRB(12, hosted ? 8 : 8, 12, 8),
      child: Column(
        children: [
          if (!hosted)
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => context.go('/portal'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
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
                  _MobileSourceFilterButton(
                    sources: sources,
                    availableSources: _availableSources(),
                    onToggle: _toggleSource,
                  ),
                  IconButton(
                    tooltip: l10n.musicDeckManageAccounts,
                    onPressed: _openAccounts,
                    icon: Badge(
                      isLabelVisible:
                          (platform?.connectedStatuses.length ?? 0) > 0,
                      child: const Icon(Icons.cloud_outlined),
                    ),
                  ),
                ],
              ),
            ),
          if (!hosted) ...[
            const SizedBox(height: 8),
            MusicDeckMobileNavigation(
              selected: _section,
              onSelected: _selectSection,
            ),
          ],
          if (hosted &&
              _section != MusicDeckSection.home &&
              _collection == null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: MobileSubpageBackButton(
                key: const ValueKey<String>('music-mobile-section-back'),
                onPressed: () => _selectSection(MusicDeckSection.home),
              ),
            ),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 8),
          Expanded(
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
      return content;
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
            .loadPlaylistTracks(playlist);
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
    final musicController = ref.read(musicCenterControllerProvider.notifier);
    await musicController.loadPlatformInfo();
    if (!mounted) {
      return;
    }
    ref.invalidate(musicPlatformLibraryProvider);
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

class _MobileSourceFilterButton extends StatelessWidget {
  const _MobileSourceFilterButton({
    required this.sources,
    required this.availableSources,
    required this.onToggle,
  });

  final Set<MusicPlatform> sources;
  final List<MusicPlatform> availableSources;
  final ValueChanged<MusicPlatform> onToggle;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MusicPlatform>(
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
      icon: const Icon(Icons.tune_rounded, size: 20),
    );
  }
}

class _WideNowPanel extends ConsumerWidget {
  const _WideNowPanel({required this.platform});

  final MusicPlatformLibraryState? platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.musicColors;
    final center = ref.watch(musicCenterControllerProvider).asData?.value;
    final track = center?.activeTrack;
    final statuses =
        platform?.connectedStatuses ?? const <MusicPlatformStatus>[];
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
