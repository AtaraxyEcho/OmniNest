import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/router.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/music/application/music_portal_integration.dart';
import 'package:omninest/features/portal/application/portal_dashboard_providers.dart';
import 'package:omninest/features/reader/domain/reader_dashboard.dart';
import 'package:omninest/features/search/application/search_controller.dart';
import 'package:omninest/features/search/domain/search_result.dart';
import 'package:omninest/features/video/domain/movie_detail_routes.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/photos/domain/photo.dart';

/// Ctrl+K 全局搜索命令面板。按 OmniNest Command Palette 设计稿复刻（浅/深主题）。
bool _globalSearchOpen = false;

Future<void> showGlobalSearchDialog(BuildContext context) async {
  if (_globalSearchOpen) {
    return;
  }
  _globalSearchOpen = true;
  try {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x990D1117),
      builder: (context) => const _CommandPaletteDialog(),
    );
  } finally {
    _globalSearchOpen = false;
  }
}

/// 设计稿双主题色板（Light: F7F8F6 纸感 / Dark: 0D1117 架构终端）。
class _Palette {
  const _Palette.light()
    : isDark = false,
      canvas = const Color(0xFFF7F8F6),
      surface = const Color(0xFFFFFFFF),
      surfaceSub = const Color(0xFFF7F9F7),
      surfaceMuted = const Color(0xFFF0F2EF),
      surfaceActive = const Color(0xFFE7EAE6),
      ink = const Color(0xFF1A1D1B),
      inkMuted = const Color(0xFF58605B),
      inkPlaceholder = const Color(0xFF8A938D),
      icon = const Color(0xFF58605B),
      hairline = const Color(0xFFE2E8F0),
      border = const Color(0xFFD2D7D2),
      accent = const Color(0xFF0B6B61),
      statusOk = const Color(0xFF217A45),
      kbdBg = const Color(0xFFF0F2EF),
      kbdBorder = const Color(0xFFD2D7D2),
      scrim = const Color(0xCCF7F8F6),
      panelShadow = true;

  const _Palette.dark()
    : isDark = true,
      canvas = const Color(0xFF0D1117),
      surface = const Color(0xFF161B22),
      surfaceSub = const Color(0xFF161B22),
      surfaceMuted = const Color(0xFF1F242C),
      surfaceActive = const Color(0xFF21262D),
      ink = const Color(0xFFEDEDED),
      inkMuted = const Color(0xFF8B949E),
      inkPlaceholder = const Color(0xFF484F58),
      icon = const Color(0xFF94A3B8),
      hairline = const Color(0xFF30363D),
      border = const Color(0xFF30363D),
      accent = const Color(0xFF79D6C8),
      statusOk = const Color(0xFF10B981),
      kbdBg = const Color(0xFF1F242C),
      kbdBorder = const Color(0xFF30363D),
      scrim = const Color(0xCC0D1117),
      panelShadow = false;

  factory _Palette.of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const _Palette.dark()
          : const _Palette.light();

  final bool isDark;
  final Color canvas;
  final Color surface;
  final Color surfaceSub;
  final Color surfaceMuted;
  final Color surfaceActive;
  final Color ink;
  final Color inkMuted;
  final Color inkPlaceholder;
  final Color icon;
  final Color hairline;
  final Color border;
  final Color accent;
  final Color statusOk;
  final Color kbdBg;
  final Color kbdBorder;
  final Color scrim;
  final bool panelShadow;
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
    this.progress,
    this.trailing,
    this.kbds = const [],
  });

  final String title;
  final String subtitle;
  final String type;
  final String? route;
  final String? thumbnailUrl;
  final double? progress;
  final String? trailing;
  final List<String> kbds;
}

class _CommandPaletteDialog extends ConsumerStatefulWidget {
  const _CommandPaletteDialog();

  @override
  ConsumerState<_CommandPaletteDialog> createState() =>
      _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends ConsumerState<_CommandPaletteDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  _PaletteTab _tab = _PaletteTab.all;
  int _highlight = 0;
  final List<String> _recentQueries = [];

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
    _recentQueries
      ..remove(q)
      ..insert(0, q);
    if (_recentQueries.length > 8) {
      _recentQueries.removeRange(8, _recentQueries.length);
    }
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
            thumbnailUrl: item.coverUrl,
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
            thumbnailUrl: item.coverUrl,
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
            route: '/files',
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
            'file' => '/files',
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
          thumbnailUrl: item.thumbnailUrl,
        ),
      );
    }

    hits.addAll(_commands(l10n));
    return hits;
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

  List<_Hit> _commands(AppLocalizations l10n) {
    return [
      _Hit(
        title: l10n.portalDockFiles,
        subtitle: l10n.searchGroupFile,
        type: 'command',
        route: '/files',
        kbds: const ['G', 'F'],
      ),
      _Hit(
        title: l10n.portalDockMusic,
        subtitle: l10n.searchGroupMusic,
        type: 'command',
        route: '/music',
        kbds: const ['G', 'M'],
      ),
      _Hit(
        title: l10n.portalDockMovies,
        subtitle: l10n.searchGroupVideo,
        type: 'command',
        route: '/video',
        kbds: const ['G', 'V'],
      ),
      _Hit(
        title: l10n.searchGroupBook,
        subtitle: l10n.searchGroupBook,
        type: 'command',
        route: '/reader',
        kbds: const ['G', 'B'],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = _Palette.of(context);
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
            if (hit.trailing == 'query') {
              _controller.text = hit.title;
              ref.read(searchQueryProvider.notifier).updateQuery(hit.title);
              setState(() => _highlight = 0);
            } else {
              _remember(query);
              _go(hit.route);
            }
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
                            color: const Color(0x0F1A1D1B),
                            blurRadius: 36,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: const Color(0x0A1A1D1B),
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
                                      _remember(query);
                                      _go(hit.route);
                                    },
                                  );
                                }
                                return _listRow(
                                  p,
                                  hit,
                                  selected: index == highlight,
                                  onTap: () {
                                    if (hit.trailing == 'query') {
                                      _controller.text = hit.title;
                                      ref
                                          .read(searchQueryProvider.notifier)
                                          .updateQuery(hit.title);
                                      setState(() => _highlight = 0);
                                    } else {
                                      _remember(query);
                                      _go(hit.route);
                                    }
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
  Widget _searchBar(_Palette p, AppLocalizations l10n) {
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
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(
                    fontSize: 15,
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
                      fontSize: 15,
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
                    _remember(value);
                    if (filteredSafe().isNotEmpty) {
                      _go(filteredSafe().first.route);
                    }
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

  Widget _filterBar(_Palette p, AppLocalizations l10n) {
    final tabs = <(_PaletteTab, String, String)>[
      (_PaletteTab.all, l10n.searchScopeAll, '1'),
      (_PaletteTab.video, l10n.searchGroupVideo, '2'),
      (_PaletteTab.music, l10n.searchGroupMusic, '3'),
      (_PaletteTab.book, l10n.searchGroupBook, '4'),
      (_PaletteTab.photo, l10n.searchGroupPhoto, '5'),
      (_PaletteTab.file, l10n.searchGroupFile, '6'),
      (_PaletteTab.command, l10n.searchGroupCommand, '7'),
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

  Widget _empty(_Palette p, AppLocalizations l10n, String query) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          query.isEmpty ? l10n.searchEmptyQuery : l10n.searchEmptyResult,
          style: TextStyle(color: p.inkMuted, fontSize: 13),
        ),
      ),
    );
  }

  Widget _listRow(
    _Palette p,
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
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: p.ink,
                  ),
                ),
              ),
              if (hit.subtitle.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  hit.subtitle,
                  style: TextStyle(fontSize: 11, color: p.inkMuted),
                ),
              ],
              if (hit.kbds.isNotEmpty) ...[
                const SizedBox(width: 10),
                for (final k in hit.kbds) ...[
                  _Kbd(label: k, p: p),
                  const SizedBox(width: 4),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _mediaCard(
    _Palette p,
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
                    child:
                        (hit.thumbnailUrl?.isEmpty ?? true)
                            ? ColoredBox(
                              color: p.surfaceMuted,
                              child: Icon(
                                Icons.movie_outlined,
                                size: 18,
                                color: p.inkMuted,
                              ),
                            )
                            : Image.network(
                              hit.thumbnailUrl!,
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (_, _, _) => ColoredBox(
                                    color: p.surfaceMuted,
                                    child: Icon(
                                      Icons.movie_outlined,
                                      size: 18,
                                      color: p.inkMuted,
                                    ),
                                  ),
                            ),
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
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: p.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hit.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: p.inkMuted),
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
                              fontSize: 10,
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

  Widget _footer(_Palette p, AppLocalizations l10n) {
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
          Text('OmniNest', style: TextStyle(fontSize: 11, color: p.inkMuted)),
        ],
      ),
    );
  }

  Widget _hint(_Palette p, String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Kbd(label: key, p: p),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, color: p.inkMuted)),
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
  final _Palette p;
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
          fontSize: 11,
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
  final _Palette p;
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
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? p.ink : p.inkMuted,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              shortcut,
              style: TextStyle(
                fontSize: 10,
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
