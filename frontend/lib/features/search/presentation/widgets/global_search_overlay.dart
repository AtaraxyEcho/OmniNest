import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/router.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/command_palette_colors.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/log/dev_log.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/core/utils/image_decode_width.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/music/application/music_portal_integration.dart';
import 'package:omninest/features/portal/application/portal_dashboard_providers.dart';
import 'package:omninest/features/reader/application/reader_image_provider.dart';
import 'package:omninest/features/reader/domain/reader_dashboard.dart';
import 'package:omninest/features/search/application/search_controller.dart';
import 'package:omninest/features/search/domain/search_result.dart';
import 'package:omninest/features/search/presentation/theme/search_overlay_colors.dart';
import 'package:omninest/features/video/domain/movie_detail_routes.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ctrl+K 全局搜索命令面板。按 OmniNest Command Palette 设计稿复刻（浅/深主题）。
bool _globalSearchOpen = false;

Future<void> showGlobalSearchDialog(BuildContext context) async {
  if (_globalSearchOpen) {
    return;
  }
  _globalSearchOpen = true;
  try {
    await showWorkstationDialog<void>(
      context: context,
      barrierColor: SearchOverlayColors.barrier,
      builder: (context) => const _CommandPaletteDialog(),
    );
  } finally {
    _globalSearchOpen = false;
  }
}

enum _PaletteTab { all, video, music, book, photo, file, command }

extension on _PaletteTab {
  bool matches(String type) => switch (this) {
    _PaletteTab.all => true,
    _PaletteTab.video => type == 'video',
    _PaletteTab.music => type == 'music',
    _PaletteTab.book => type == 'book',
    _PaletteTab.photo => type == 'photo',
    _PaletteTab.file => type == 'file',
    _PaletteTab.command => type == 'command',
  };
}

class _Hit {
  const _Hit({
    required this.title,
    required this.subtitle,
    required this.type,
    required this.route,
    this.thumbnailUrl,
    this.readerItemId,
    this.musicTrackId,
    this.progress,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String type;
  final String? route;
  final String? thumbnailUrl;

  /// 阅读封面是鉴权接口，不能直接交给 Image.network 当 URL 用。
  final String? readerItemId;

  /// 音乐命中在跳转后按曲目 ID 起播，避免只落到音乐首页。
  final String? musicTrackId;
  final double? progress;
  final String? trailing;
}

class _CommandPaletteDialog extends ConsumerStatefulWidget {
  const _CommandPaletteDialog();

  @override
  ConsumerState<_CommandPaletteDialog> createState() =>
      _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends ConsumerState<_CommandPaletteDialog> {
  /// 搜索历史按账号隔离：同一设备切换账号不能看到上一个人的搜索词。
  String get _recentQueriesKey {
    final userId = ref.read(authSessionProvider).value?.user?.id;
    return 'search.recent_queries.v2.${userId ?? 'anonymous'}';
  }

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  _PaletteTab _tab = _PaletteTab.all;
  int _highlight = 0;
  final List<String> _recentQueries = [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecentQueries());
  }

  Future<void> _loadRecentQueries() async {
    // 存储键要跨异步边界使用，必须在 await 之前取好：getter 内的 ref.read
    // 若排在 await 之后，面板已关闭时就会命中已卸载的 Widget。
    final storageKey = _recentQueriesKey;
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getStringList(storageKey) ?? const [];
    if (!mounted) {
      return;
    }
    setState(() {
      _recentQueries
        ..clear()
        ..addAll(saved);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _go(String? route) {
    final GoRouter router =
        GoRouter.maybeOf(context) ?? ref.read(appRouterProvider);
    Navigator.of(context).pop();
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        router.go(route);
      });
    }
  }

  void _remember(String query) {
    final q = query.trim();
    if (q.isEmpty) {
      return;
    }
    // 命中跳转先记历史再 pop 本面板，写盘回调可能落在卸载之后：
    // 存储键与待写列表都在 pop 前定格，回调只碰 SharedPreferences，不碰 ref/context。
    final storageKey = _recentQueriesKey;
    _recentQueries
      ..remove(q)
      ..insert(0, q);
    if (_recentQueries.length > 8) {
      _recentQueries.removeRange(8, _recentQueries.length);
    }
    unawaited(
      _persistRecentQueries(storageKey, List<String>.from(_recentQueries)),
    );
  }

  Future<void> _persistRecentQueries(
    String storageKey,
    List<String> snapshot,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(storageKey, snapshot);
    } on Exception catch (error) {
      devLog('搜索历史写入失败: ${error.runtimeType}');
    }
  }

  /// 激活一条命中：历史词回填搜索框，其它目标先补齐上下文再跳转。
  void _activateHit(_Hit hit, String query) {
    if (hit.trailing == 'query') {
      _controller.text = hit.title;
      ref.read(searchQueryProvider.notifier).updateQuery(hit.title);
      setState(() => _highlight = 0);
      return;
    }
    final trackId = hit.musicTrackId;
    if (trackId != null && trackId.isNotEmpty) {
      // 先起播再跳页：音乐页无需再按搜索词重新定位。
      unawaited(ref.read(musicPortalActionsProvider).playTrackById(trackId));
    }
    _remember(query);
    _go(hit.route);
  }

  List<_Hit> _buildHits({
    required MovieDashboard? dashboard,
    required ReaderDashboard? reader,
    required PhotoDashboard? photos,
    required MusicPortalSnapshot? music,
    required List<FileNode>? files,
    required List<SearchResult>? api,
  }) {
    final l10n = AppLocalizations.of(context);
    final query = _controller.text.trim();
    final hits = <_Hit>[];

    if (query.isEmpty) {
      for (final q in _recentQueries) {
        hits.add(
          _Hit(
            title: q,
            subtitle: l10n.searchHint,
            type: 'command',
            route: null,
            trailing: 'query',
          ),
        );
      }
    }

    if (dashboard != null) {
      for (final item in dashboard.recentlyAdded) {
        hits.add(_videoHit(item, section: l10n.videoSectionRecent));
      }
      for (final item in dashboard.continueWatching) {
        final prog =
            item.durationSeconds > 0
                ? (item.positionSeconds / item.durationSeconds).clamp(0.0, 1.0)
                : (item.progressPercent / 100.0).clamp(0.0, 1.0);
        hits.add(
          _Hit(
            title: item.title,
            subtitle: l10n.videoSectionContinueWatching,
            type: 'video',
            route: moviePlayRoute(item.id),
            thumbnailUrl: item.posterUrl,
            progress: prog,
          ),
        );
      }
    }

    if (reader != null) {
      for (final item in reader.continueReading) {
        hits.add(
          _Hit(
            title: item.title,
            subtitle: l10n.videoSectionContinueWatching,
            type: 'book',
            route: '/reader/items/${item.id}',
            readerItemId: item.id,
          ),
        );
      }
      for (final item in reader.recentItems) {
        hits.add(
          _Hit(
            title: item.title,
            subtitle: l10n.searchGroupBook,
            type: 'book',
            route: '/reader/items/${item.id}',
            readerItemId: item.id,
          ),
        );
      }
    }

    if (photos != null) {
      for (final item in photos.recentPhotos) {
        hits.add(
          _Hit(
            title: item.title,
            subtitle: l10n.searchGroupPhoto,
            type: 'photo',
            route: '/photos/${item.id}',
            thumbnailUrl: item.coverUrl,
          ),
        );
      }
    }

    if (music != null) {
      for (final track in music.recentTracks) {
        hits.add(
          _Hit(
            title: track.title,
            subtitle: track.artistName,
            type: 'music',
            route: '/music',
            musicTrackId: track.id,
            thumbnailUrl: track.listCoverUrl ?? track.coverUrl,
          ),
        );
      }
    }

    if (files != null) {
      for (final node in files) {
        hits.add(
          _Hit(
            title: node.name,
            subtitle: l10n.searchGroupFile,
            type: 'file',
            route: '/files/preview/${node.id}',
          ),
        );
      }
    }

    for (final item in api ?? const <SearchResult>[]) {
      hits.add(
        _Hit(
          title: item.title,
          subtitle: item.subtitle,
          type: item.type,
          route: switch (item.type) {
            'file' => '/files/preview/${item.id}',
            'book' => '/reader/items/${item.id}',
            // 分集进剧集详情选集；禁止用分集 id 打开影片详情。
            'video' => movieDetailRouteFromIds(
              videoItemId: item.id,
              seriesId: item.seriesId,
            ),
            'photo' => '/photos/${item.id}',
            'music' => '/music',
            _ => null,
          },
          readerItemId: item.type == 'book' ? item.id : null,
          musicTrackId: item.type == 'music' ? item.id : null,
          thumbnailUrl: item.type == 'book' ? null : item.thumbnailUrl,
        ),
      );
    }

    hits.addAll(_commands(l10n));
    // 本地看板与远端搜索会命中同一实体；按类型、目标路由和标题去重，
    // 避免同一部电影/同一本书出现两三次。
    final deduped = <_Hit>[];
    final seen = <String>{};
    for (final hit in hits) {
      final key = '${hit.type}|${hit.route ?? ''}|${hit.title}';
      if (seen.add(key)) {
        deduped.add(hit);
      }
    }
    return deduped;
  }

  _Hit _videoHit(MovieVideoItem item, {required String section}) {
    return _Hit(
      title: item.title,
      subtitle: section,
      type: 'video',
      route: movieDetailRoute(item),
      thumbnailUrl: item.posterImageUrl,
    );
  }

  /// Tab / Shift+Tab 循环切换筛选页签，越界回绕。
  void _cycleTab(int delta) {
    final tabs = _PaletteTab.values;
    final next = (_tab.index + delta) % tabs.length;
    if (tabs[next] == _tab) {
      return;
    }
    setState(() {
      _tab = tabs[next];
      _highlight = 0;
    });
  }

  /// 数字键 1~7 直达对应页签；返回是否消费了这次按键。
  ///
  /// 必须带 Alt/Ctrl/Meta：搜索词本身经常包含年份、卷号与格式数字，
  /// 裸数字不能从输入框手里抢走。
  bool _selectTabByDigit(LogicalKeyboardKey key) {
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isAltPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed) {
      return false;
    }
    const digits = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
    ];
    final index = digits.indexOf(key);
    if (index < 0 || index >= _PaletteTab.values.length) {
      return false;
    }
    if (_PaletteTab.values[index] == _tab) {
      return true;
    }
    setState(() {
      _tab = _PaletteTab.values[index];
      _highlight = 0;
    });
    return true;
  }

  List<_Hit> _commands(AppLocalizations l10n) {
    return [
      _Hit(
        title: l10n.portalDockFiles,
        subtitle: l10n.searchGroupFile,
        type: 'command',
        route: '/files',
      ),
      _Hit(
        title: l10n.portalDockMusic,
        subtitle: l10n.searchGroupMusic,
        type: 'command',
        route: '/music',
      ),
      _Hit(
        title: l10n.portalDockMovies,
        subtitle: l10n.searchGroupVideo,
        type: 'command',
        route: '/video',
      ),
      _Hit(
        title: l10n.searchGroupBook,
        subtitle: l10n.searchGroupBook,
        type: 'command',
        route: '/reader',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.commandPaletteColors;
    final dashboard = ref.watch(portalMovieDashboardProvider).asData?.value;
    final query = _controller.text.trim();
    final all = _buildHits(
      dashboard: dashboard,
      reader: ref.watch(portalReaderDashboardProvider).asData?.value,
      photos: ref.watch(portalPhotoDashboardProvider).asData?.value,
      music: ref.watch(portalMusicSnapshotProvider).asData?.value,
      files: ref.watch(portalRecentFilesProvider).asData?.value,
      api: ref.watch(searchResultsProvider).asData?.value,
    );
    final visible = all.where((h) => _tab.matches(h.type)).toList();
    final q = query.toLowerCase();
    final filtered =
        query.isEmpty
            ? visible
            : visible
                .where(
                  (h) =>
                      h.title.toLowerCase().contains(q) ||
                      h.subtitle.toLowerCase().contains(q),
                )
                .toList();
    final highlight = _highlight.clamp(
      0,
      filtered.isEmpty ? 0 : filtered.length - 1,
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).pop();
        },
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.tab) {
            // 页签切换在空结果时也要可用：换页签正是恢复手段。
            _cycleTab(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
            return KeyEventResult.handled;
          }
          if (_selectTabByDigit(event.logicalKey)) {
            return KeyEventResult.handled;
          }
          if (filtered.isEmpty) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            setState(() => _highlight = (_highlight + 1) % filtered.length);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            setState(
              () =>
                  _highlight =
                      (_highlight - 1 + filtered.length) % filtered.length,
            );
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            final hit = filtered[_highlight.clamp(0, filtered.length - 1)];
            _activateHit(hit, query);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.fromLTRB(16, 48, 16, 32),
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780, maxHeight: 640),
            child: Container(
              decoration: BoxDecoration(
                color: p.surface,
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(p.isDark ? 4 : 8),
                boxShadow:
                    p.panelShadow
                        ? [
                          BoxShadow(
                            color: SearchOverlayColors.hintTile,
                            blurRadius: 36,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: SearchOverlayColors.hintTileSoft,
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ]
                        : const [],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _searchBar(p, l10n),
                  _filterBar(p, l10n),
                  Flexible(
                    child:
                        filtered.isEmpty
                            ? _empty(p, l10n, query)
                            : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                12,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final hit = filtered[index];
                                if (hit.progress != null) {
                                  return _mediaCard(
                                    p,
                                    hit,
                                    selected: index == highlight,
                                    onTap: () {
                                      _activateHit(hit, query);
                                    },
                                  );
                                }
                                return _listRow(
                                  p,
                                  hit,
                                  selected: index == highlight,
                                  onTap: () {
                                    _activateHit(hit, query);
                                  },
                                );
                              },
                            ),
                  ),
                  _footer(p, l10n),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 设计稿 Top Search Input Bar：h-56 / px-20 / icon-22 / text-15 / ESC kbd。
  Widget _searchBar(CommandPaletteColors p, AppLocalizations l10n) {
    return Material(
      color: p.surface,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.hairline)),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 22, color: p.icon),
            const SizedBox(width: 14),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  textAlignVertical: TextAlignVertical.center,
                  cursorColor: p.accent,
                  cursorWidth: 1.5,
                  cursorHeight: 20,
                  cursorRadius: Radius.zero,
                  keyboardType: TextInputType.webSearch,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(
                    fontSize: AppTypography.bodyLarge,
                    height: 1.0,
                    color: p.ink,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    isCollapsed: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    hintText: l10n.searchPaletteHint,
                    hintStyle: TextStyle(
                      color: p.inkPlaceholder,
                      fontSize: AppTypography.bodyLarge,
                      height: 1.0,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  onChanged: (_) {
                    ref
                        .read(searchQueryProvider.notifier)
                        .updateQuery(_controller.text);
                    setState(() => _highlight = 0);
                  },
                  onSubmitted: (value) {
                    final hits = filteredSafe();
                    if (hits.isEmpty) {
                      return;
                    }
                    final index = _highlight.clamp(0, hits.length - 1);
                    _activateHit(hits[index], value);
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            _Kbd(label: 'ESC', p: p, muted: true),
          ],
        ),
      ),
    );
  }

  List<_Hit> filteredSafe() {
    final all = _buildHits(
      dashboard: ref.read(portalMovieDashboardProvider).asData?.value,
      reader: ref.read(portalReaderDashboardProvider).asData?.value,
      photos: ref.read(portalPhotoDashboardProvider).asData?.value,
      music: ref.read(portalMusicSnapshotProvider).asData?.value,
      files: ref.read(portalRecentFilesProvider).asData?.value,
      api: ref.read(searchResultsProvider).asData?.value,
    );
    final query = _controller.text.trim().toLowerCase();
    return all
        .where((h) => _tab.matches(h.type))
        .where(
          (h) =>
              query.isEmpty ||
              h.title.toLowerCase().contains(query) ||
              h.subtitle.toLowerCase().contains(query),
        )
        .toList();
  }

  Widget _filterBar(CommandPaletteColors p, AppLocalizations l10n) {
    final tabs = <(_PaletteTab, String, String)>[
      (_PaletteTab.all, l10n.searchScopeAll, 'Alt+1'),
      (_PaletteTab.video, l10n.searchGroupVideo, 'Alt+2'),
      (_PaletteTab.music, l10n.searchGroupMusic, 'Alt+3'),
      (_PaletteTab.book, l10n.searchGroupBook, 'Alt+4'),
      (_PaletteTab.photo, l10n.searchGroupPhoto, 'Alt+5'),
      (_PaletteTab.file, l10n.searchGroupFile, 'Alt+6'),
      (_PaletteTab.command, l10n.searchGroupCommand, 'Alt+7'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: p.isDark ? p.surface : p.surfaceSub,
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (tab, label, key) in tabs)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _TabChip(
                  label: label,
                  shortcut: key,
                  selected: _tab == tab,
                  p: p,
                  onTap:
                      () => setState(() {
                        _tab = tab;
                        _highlight = 0;
                      }),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _empty(CommandPaletteColors p, AppLocalizations l10n, String query) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          query.isEmpty ? l10n.searchEmptyQuery : l10n.searchEmptyResult,
          style: TextStyle(
            color: p.inkMuted,
            fontSize: AppTypography.bodyMedium,
          ),
        ),
      ),
    );
  }

  Widget _listRow(
    CommandPaletteColors p,
    _Hit hit, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? p.surfaceMuted : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: p.hairline.withValues(alpha: 0.5)),
            ),
          ),
          child: Row(
            children: [
              Icon(_iconFor(hit.type), size: 18, color: p.inkMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hit.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w500,
                    color: p.ink,
                  ),
                ),
              ),
              if (hit.subtitle.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  hit.subtitle,
                  style: TextStyle(
                    fontSize: AppTypography.labelSmall,
                    color: p.inkMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _hitThumbnail(CommandPaletteColors p, _Hit hit) {
    final fallback = ColoredBox(
      color: p.surfaceMuted,
      child: Icon(Icons.movie_outlined, size: 18, color: p.inkMuted),
    );
    final readerItemId = hit.readerItemId;
    if (readerItemId != null && readerItemId.isNotEmpty) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final cacheWidth = quantizedDecodeWidth(
        logicalWidth: 116,
        devicePixelRatio: dpr,
      );
      return ref
          .watch(coverBytesProvider(readerItemId))
          .when(
            data:
                (bytes) =>
                    bytes == null || bytes.isEmpty
                        ? fallback
                        : Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          cacheWidth: cacheWidth,
                          errorBuilder: (_, _, _) => fallback,
                        ),
            loading: () => fallback,
            error: (_, _) => fallback,
          );
    }
    final url = hit.thumbnailUrl;
    if (url == null || url.isEmpty) {
      return fallback;
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: quantizedDecodeWidth(
        logicalWidth: 116,
        devicePixelRatio: dpr,
      ),
      cacheHeight: quantizedDecodeWidth(
        logicalWidth: 68,
        devicePixelRatio: dpr,
      ),
      errorBuilder: (_, _, _) => fallback,
    );
  }

  Widget _mediaCard(
    CommandPaletteColors p,
    _Hit hit, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final progress = hit.progress ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: p.surface,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? p.surfaceMuted : p.surface,
              border: Border.all(color: selected ? p.border : p.hairline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    width: 116,
                    height: 68,
                    child: _hitThumbnail(p, hit),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hit.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppTypography.bodySmall,
                          fontWeight: FontWeight.w600,
                          color: p.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hit.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppTypography.labelSmall,
                          color: p.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 3,
                                backgroundColor: p.surfaceActive,
                                valueColor: AlwaysStoppedAnimation(p.accent),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(progress * 100).round()}%',
                            style: TextStyle(
                              fontSize: AppTypography.labelMicro,
                              color: p.inkMuted,
                              fontFeatures: const [],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(CommandPaletteColors p, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.hairline)),
      ),
      child: Row(
        children: [
          _hint(p, '↑↓', l10n.searchFooterNavigate),
          const SizedBox(width: 14),
          _hint(p, '↵', l10n.searchFooterSelect),
          const SizedBox(width: 14),
          _hint(p, 'Tab', l10n.searchFooterFilter),
          const SizedBox(width: 14),
          _hint(p, 'Esc', l10n.searchFooterClose),
          const Spacer(),
          Container(width: 6, height: 6, color: p.statusOk),
          const SizedBox(width: 8),
          Text(
            'OmniNest',
            style: TextStyle(
              fontSize: AppTypography.labelSmall,
              color: p.inkMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hint(CommandPaletteColors p, String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Kbd(label: key, p: p),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: AppTypography.labelSmall,
            color: p.inkMuted,
          ),
        ),
      ],
    );
  }

  IconData _iconFor(String type) {
    return switch (type) {
      'file' => Icons.insert_drive_file_outlined,
      'book' => Icons.menu_book_outlined,
      'video' => Icons.movie_outlined,
      'photo' => Icons.photo_outlined,
      'music' => Icons.music_note_outlined,
      'command' => Icons.bolt_outlined,
      _ => Icons.search_rounded,
    };
  }
}

class _Kbd extends StatelessWidget {
  const _Kbd({required this.label, required this.p, this.muted = false});

  final String label;
  final CommandPaletteColors p;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: muted ? p.surfaceMuted : p.kbdBg,
        border: Border.all(color: muted ? p.hairline : p.kbdBorder),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppTypography.labelSmall,
          height: 1.0,
          color: muted ? p.inkMuted : p.ink,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.08,
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.shortcut,
    required this.selected,
    required this.p,
    required this.onTap,
  });

  final String label;
  final String shortcut;
  final bool selected;
  final CommandPaletteColors p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? p.surfaceActive : Colors.transparent,
          border: Border.all(color: selected ? p.border : Colors.transparent),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected && p.isDark) ...[
              Container(width: 5, height: 5, color: p.accent),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: AppTypography.labelSmall,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? p.ink : p.inkMuted,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              shortcut,
              style: TextStyle(
                fontSize: AppTypography.labelMicro,
                color: selected ? p.inkMuted : p.inkPlaceholder,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
