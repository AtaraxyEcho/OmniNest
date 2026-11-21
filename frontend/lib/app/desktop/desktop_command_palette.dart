import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_sidebar.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/files/file_dashboard.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/photos/photo_dashboard.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';
import 'package:omninest/features/video/video_dashboard.dart';

// 范围筛选行（样例 `Shell.tsx:381` 的 tablist）单开一份 part，主库压回 800 行内。
part 'desktop_command_palette_scope.dart';

enum DesktopPaletteScope { all, movies, photos, music, files, reader }

@immutable
class _Command {
  const _Command({
    required this.id,
    required this.group,
    required this.label,
    required this.icon,
    required this.run,
    this.hint,
    this.imageUrl,
    this.coverKind = DesktopCoverKind.network,
    this.readerItemId,
  });

  final String id;
  final String group;
  final String label;
  final IconData icon;
  final VoidCallback run;
  final String? hint;
  final String? imageUrl;
  final DesktopCoverKind coverKind;
  final String? readerItemId;
}

/// 命令面板（样例 `Palette`）：Ctrl+K 唤起，跨模块查找 + 命令执行。
class DesktopCommandPalette extends ConsumerStatefulWidget {
  const DesktopCommandPalette({super.key});

  @override
  ConsumerState<DesktopCommandPalette> createState() =>
      _DesktopCommandPaletteState();
}

class _DesktopCommandPaletteState extends ConsumerState<DesktopCommandPalette> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  DesktopPaletteScope _scope = DesktopPaletteScope.all;
  int _selected = 0;
  String _text = '';

  @override
  void initState() {
    super.initState();
    _query.addListener(() {
      if (_query.text != _text) {
        setState(() {
          _text = _query.text;
          _selected = 0;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _inputFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _close() =>
      ref.read(desktopShellProvider.notifier).setCommandPalette(false);

  void _run(_Command command) {
    _close();
    command.run();
  }

  /// 样例的三档打分：前缀 > 子串 > 子序列。
  int _score(_Command command, String needle) {
    final haystack = '${command.label} ${command.hint ?? ''}'.toLowerCase();
    if (haystack.startsWith(needle)) {
      return 3;
    }
    if (haystack.contains(needle)) {
      return 2;
    }
    var index = 0;
    for (final unit in haystack.split('')) {
      if (index < needle.length && unit == needle[index]) {
        index++;
      }
    }
    return index == needle.length ? 1 : 0;
  }

  List<_Command> _commands(AppLocalizations l10n) {
    final shell = ref.read(desktopShellProvider.notifier);
    final goGroup = l10n.desktopGroupGoTo;
    final actionGroup = l10n.desktopGroupActions;
    final commands = <_Command>[
      for (final item in desktopNavItems(l10n))
        _Command(
          id: 'go-${item.route}',
          group: goGroup,
          label: item.label,
          hint: 'Alt ${item.shortcut}',
          icon: item.icon,
          run: () => desktopGo(context, item.route),
        ),
      _Command(
        id: 'go-settings',
        group: goGroup,
        label: l10n.desktopNavSettings,
        hint: 'Ctrl ,',
        icon: DesktopIcons.settings,
        run: () => desktopGo(context, DesktopRoutes.settings),
      ),
    ];

    // 组序照样例 `Shell.tsx:345-359`：Go to → Music → Movies → Reader →
    // Photos → Files → Actions。这里按顺序 add，展示层只按 group 归堆。
    final music = ref.watch(musicPortalSnapshotProvider).asData?.value;
    for (final item in music?.recentTracks ?? const <MusicPortalTrack>[]) {
      commands.add(
        _Command(
          id: 'track-${item.id}',
          group: l10n.desktopScopeMusic,
          label: item.title,
          hint: item.artistName,
          icon: DesktopIcons.music,
          imageUrl: item.listCoverUrl ?? item.coverUrl,
          coverKind: DesktopCoverKind.music,
          run:
              () => ref.read(musicPortalActionsProvider).playTrackById(item.id),
        ),
      );
    }
    final movies = ref.watch(movieDashboardProvider).asData?.value;
    for (final item in movies?.recentlyAdded ?? const <MovieVideoItem>[]) {
      commands.add(
        _Command(
          id: 'movie-${item.id}',
          group: l10n.desktopScopeMovies,
          label: item.title,
          hint: '${item.year} · ${item.genres.join(' / ')}',
          icon: DesktopIcons.film,
          imageUrl: item.posterImageUrl,
          run: () => desktopPush(context, DesktopRoutes.movieDetail(item.id)),
        ),
      );
    }
    final reader = ref.watch(readerDashboardProvider).asData?.value;
    for (final item in reader?.recentItems ?? const <ReaderItem>[]) {
      commands.add(
        _Command(
          id: 'book-${item.id}',
          group: l10n.desktopScopeReader,
          label: item.title,
          hint: item.authorName,
          icon: DesktopIcons.book,
          imageUrl: item.coverUrl,
          coverKind: DesktopCoverKind.reader,
          readerItemId: item.id,
          run: () => desktopPush(context, DesktopRoutes.bookDetail(item.id)),
        ),
      );
    }
    final photos = ref.watch(photoDashboardProvider).asData?.value;
    for (final item in photos?.recentPhotos ?? const <PhotoItem>[]) {
      commands.add(
        _Command(
          id: 'photo-${item.id}',
          group: l10n.desktopScopePhotos,
          label: item.title,
          hint: item.locationDisplay(),
          icon: DesktopIcons.image,
          imageUrl: item.coverUrl,
          run: () => desktopPush(context, DesktopRoutes.photoDetail(item.id)),
        ),
      );
    }
    final files = ref.watch(fileRecentEntriesProvider).asData?.value;
    for (final item in files ?? const <FileNode>[]) {
      commands.add(
        _Command(
          id: 'file-${item.id}',
          group: l10n.desktopScopeFiles,
          label: item.name,
          hint: item.isFolder ? null : item.nodeType,
          icon: item.isFolder ? DesktopIcons.folder : DesktopIcons.list2,
          run:
              () =>
                  item.isFolder
                      ? desktopGo(context, DesktopRoutes.files)
                      : desktopPush(
                        context,
                        DesktopRoutes.filePreview(item.id),
                      ),
        ),
      );
    }

    final playing =
        ref.watch(musicPortalSnapshotProvider).asData?.value.isPlaying ?? false;
    final isDark = DesktopSkin.of(context).isDark;
    commands.addAll([
      _Command(
        id: 'action-play',
        group: actionGroup,
        label: playing ? l10n.desktopPause : l10n.desktopPlay,
        hint: 'Space',
        icon: playing ? DesktopIcons.pause : DesktopIcons.play,
        run: () => ref.read(musicPortalActionsProvider).togglePlayback(),
      ),
      _Command(
        id: 'action-next',
        group: actionGroup,
        label: l10n.desktopActionNextTrack,
        icon: DesktopIcons.next,
        run: () => ref.read(musicPortalActionsProvider).nextTrack(),
      ),
      _Command(
        id: 'action-theme',
        group: actionGroup,
        label:
            isDark
                ? l10n.desktopActionSwitchToLight
                : l10n.desktopActionSwitchToDark,
        icon: isDark ? DesktopIcons.sun : DesktopIcons.moon,
        run:
            () => ref
                .read(appearanceControllerProvider.notifier)
                .setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark),
      ),
      _Command(
        id: 'action-sidebar',
        group: actionGroup,
        label: l10n.desktopActionToggleSidebar,
        hint: 'Ctrl B',
        icon: DesktopIcons.sidebar,
        run: shell.toggleSidebar,
      ),
      _Command(
        id: 'action-dock',
        group: actionGroup,
        label: l10n.desktopActionToggleDetails,
        hint: 'Ctrl .',
        icon: DesktopIcons.panel,
        run: shell.toggleDock,
      ),
      _Command(
        id: 'action-now-playing',
        group: actionGroup,
        label: l10n.desktopActionOpenNowPlaying,
        icon: DesktopIcons.expand,
        run: () => desktopPush(context, DesktopRoutes.nowPlaying),
      ),
      _Command(
        id: 'action-shortcuts',
        group: actionGroup,
        label: l10n.desktopActionShortcuts,
        hint: '?',
        icon: DesktopIcons.command,
        run: () => shell.setShortcuts(true),
      ),
      _Command(
        id: 'action-signout',
        group: actionGroup,
        label: l10n.desktopActionSignOut,
        icon: DesktopIcons.signOut,
        run: () => ref.read(authSessionProvider.notifier).clearSession(),
      ),
    ]);
    return commands;
  }

  String _scopeLabel(AppLocalizations l10n, DesktopPaletteScope scope) =>
      switch (scope) {
        DesktopPaletteScope.all => l10n.desktopScopeAll,
        DesktopPaletteScope.movies => l10n.desktopScopeMovies,
        DesktopPaletteScope.photos => l10n.desktopScopePhotos,
        DesktopPaletteScope.music => l10n.desktopScopeMusic,
        DesktopPaletteScope.files => l10n.desktopScopeFiles,
        DesktopPaletteScope.reader => l10n.desktopScopeReader,
      };

  bool _inScope(AppLocalizations l10n, _Command command) => switch (_scope) {
    DesktopPaletteScope.all => true,
    DesktopPaletteScope.movies => command.group == l10n.desktopScopeMovies,
    DesktopPaletteScope.photos => command.group == l10n.desktopScopePhotos,
    DesktopPaletteScope.music => command.group == l10n.desktopScopeMusic,
    DesktopPaletteScope.files => command.group == l10n.desktopScopeFiles,
    DesktopPaletteScope.reader => command.group == l10n.desktopScopeReader,
  };

  List<_Command> _results(AppLocalizations l10n, List<_Command> commands) {
    final needle = _text.trim().toLowerCase();
    final scoped = commands.where((c) => _inScope(l10n, c)).toList();
    if (needle.isEmpty) {
      if (_scope == DesktopPaletteScope.all) {
        return scoped
            .where(
              (c) =>
                  c.group == l10n.desktopGroupGoTo ||
                  c.group == l10n.desktopGroupActions,
            )
            .take(12)
            .toList();
      }
      return scoped.take(8).toList();
    }
    final scored = <(_Command, int)>[];
    for (final command in scoped) {
      final score = _score(command, needle);
      if (score > 0) {
        scored.add((command, score));
      }
    }
    // `List.sort` 不稳定，同分时次序会随实现漂移；用「分数降序、命中顺序
    // 升序」显式定序，等价于 JS `Array.sort` 的稳定行为（样例 `Shell.tsx:366`）。
    final ranked = <(_Command, int, int)>[
      for (var i = 0; i < scored.length; i++) (scored[i].$1, scored[i].$2, i),
    ];
    ranked.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      return byScore != 0 ? byScore : a.$3.compareTo(b.$3);
    });
    return ranked.take(14).map((entry) => entry.$1).toList();
  }

  void _move(int delta, int length) {
    if (length == 0) {
      return;
    }
    setState(() => _selected = (_selected + delta).clamp(0, length - 1));
    if (_scroll.hasClients) {
      final target = (_selected * 46.0) - 160;
      _scroll.animateTo(
        target.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: MotionToken.reduced(context, MotionToken.fast),
        curve: MotionToken.curve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final results = _results(l10n, _commands(l10n));
    if (_selected >= results.length) {
      _selected = results.isEmpty ? 0 : results.length - 1;
    }

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: ColoredBox(
            color:
                DesktopSkin.of(context).isDark
                    ? Colors.black.withValues(alpha: 0.50)
                    : Colors.black.withValues(alpha: 0.24),
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.sizeOf(context).height * 0.12,
                ),
                // 样例 `.palette { animation: modalin .4s var(--spring) }`：
                // 淡入 + translateY(14→0) + 从 0.94 放大，锚点在顶部中心。
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: MotionToken.reduced(context, DesktopMotion.fade),
                  curve: DesktopMotion.spring,
                  builder:
                      (context, t, child) => Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, (1 - t) * 14),
                          child: Transform.scale(
                            scale: 0.94 + 0.06 * t,
                            alignment: Alignment.topCenter,
                            child: child,
                          ),
                        ),
                      ),
                  child: GestureDetector(
                    onTap: () {},
                    child: Material(
                      color: Colors.transparent,
                      child: DesktopOutsetShadow(
                        borderRadius: BorderRadius.circular(
                          DesktopMetrics.radiusDialog,
                        ),
                        shadows: skin.shadow,
                        child: DesktopGlassSurface(
                          borderRadius: BorderRadius.circular(
                            DesktopMetrics.radiusDialog,
                          ),
                          blur: 40,
                          saturation: 1.6,
                          child: Container(
                            width: 640,
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width - 40,
                            ),
                            decoration: BoxDecoration(
                              color: skin.pop,
                              borderRadius: BorderRadius.circular(
                                DesktopMetrics.radiusDialog,
                              ),
                              border: Border.all(color: skin.line2),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _SearchField(
                                  controller: _query,
                                  focusNode: _inputFocus,
                                  onMove:
                                      (delta) => _move(delta, results.length),
                                  onSubmit: () {
                                    if (results.isNotEmpty) {
                                      _run(results[_selected]);
                                    }
                                  },
                                  onClose: _close,
                                ),
                                _ScopeRow(
                                  scope: _scope,
                                  labelOf: (value) => _scopeLabel(l10n, value),
                                  onChanged: (value) {
                                    setState(() {
                                      _scope = value;
                                      _selected = 0;
                                    });
                                    _inputFocus.requestFocus();
                                  },
                                ),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 400,
                                  ),
                                  child:
                                      results.isEmpty
                                          ? DesktopEmpty(
                                            message:
                                                _text.trim().isEmpty
                                                    ? l10n
                                                        .desktopPaletteIdleEmpty
                                                    : l10n.desktopPaletteEmpty(
                                                      _text.trim(),
                                                    ),
                                            icon: DesktopIcons.search,
                                            actionLabel:
                                                _scope ==
                                                        DesktopPaletteScope.all
                                                    ? null
                                                    : l10n
                                                        .desktopSearchEverything,
                                            onAction:
                                                () => setState(
                                                  () =>
                                                      _scope =
                                                          DesktopPaletteScope
                                                              .all,
                                                ),
                                          )
                                          : ListView.builder(
                                            controller: _scroll,
                                            shrinkWrap: true,
                                            padding: const EdgeInsets.all(8),
                                            itemCount: results.length,
                                            itemBuilder: (context, index) {
                                              final command = results[index];
                                              final showHeader =
                                                  index == 0 ||
                                                  results[index - 1].group !=
                                                      command.group;
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  if (showHeader)
                                                    DesktopEyebrow(
                                                      command.group,
                                                      padding:
                                                          const EdgeInsets.fromLTRB(
                                                            10,
                                                            10,
                                                            10,
                                                            4,
                                                          ),
                                                    ),
                                                  _PaletteRow(
                                                    command: command,
                                                    selected:
                                                        index == _selected,
                                                    onHover:
                                                        () => setState(
                                                          () =>
                                                              _selected = index,
                                                        ),
                                                    onTap: () => _run(command),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                ),
                                _PaletteFooter(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onMove,
    required this.onSubmit,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<int> onMove;
  final VoidCallback onSubmit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          Icon(
            DesktopIcons.search,
            size: DesktopMetrics.iconMedium,
            color: skin.text3,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowDown):
                    () => onMove(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp):
                    () => onMove(-1),
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onSubmitted: (_) => onSubmit(),
                cursorColor: skin.accent,
                style: DesktopType.medium(
                  skin.text,
                ).copyWith(fontSize: 16), // ignore: font_size_whitelist
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: l10n.desktopPaletteHint,
                  hintStyle: DesktopType.medium(
                    skin.text3,
                  ).copyWith(fontSize: 16), // ignore: font_size_whitelist
                ),
              ),
            ),
          ),
          DesktopIconButton(
            icon: DesktopIcons.close,
            tooltip: l10n.desktopPaletteClose,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.command,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  final _Command command;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? skin.accentWash(0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusButton),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child:
                    command.imageUrl == null
                        ? Container(
                          decoration: BoxDecoration(
                            color: skin.raise2,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            command.icon,
                            size: 15,
                            color: skin.text2,
                          ),
                        )
                        : DesktopCover(
                          url: command.imageUrl,
                          kind: command.coverKind,
                          readerItemId: command.readerItemId,
                          fallbackIcon: command.icon,
                          borderRadius: BorderRadius.circular(8),
                          iconSize: 15,
                        ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  command.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.denseStrong(skin.text),
                ),
              ),
              if (command.hint != null && command.hint!.isNotEmpty) ...[
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    command.hint!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.caption(skin.text3),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Icon(
                DesktopIcons.moveRight,
                size: 14,
                color: selected ? skin.accent : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaletteFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    Widget hint(String key, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(key, style: DesktopType.kbd(skin.text2)),
        const SizedBox(width: 4),
        Text(label, style: DesktopType.caption(skin.text3)),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          hint('↑↓', l10n.desktopPaletteNavigate),
          const SizedBox(width: 18),
          hint('↵', l10n.desktopPaletteOpen),
          const SizedBox(width: 18),
          hint('Esc', l10n.desktopPaletteClose),
        ],
      ),
    );
  }
}
