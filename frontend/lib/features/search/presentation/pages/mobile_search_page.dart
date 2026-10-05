import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/features/search/application/search_controller.dart';
import 'package:omninest/features/search/domain/search_result.dart';
import 'package:omninest/features/video/domain/movie_detail_routes.dart';

/// 全局搜索的移动端全屏覆盖层（样例 search-overlay 逐值复刻）。
///
/// 头部 48 高 r16 输入胶囊；空态 = SEARCH ACROSS OMNINEST 眉标 + 3 列
/// 范围格 + 最近搜索行；结果行 42 r13 强调色图标盒。
class MobileSearchPage extends ConsumerStatefulWidget {
  const MobileSearchPage({super.key});

  @override
  ConsumerState<MobileSearchPage> createState() => _MobileSearchPageState();
}

/// 本次会话内的最近搜索（与桌面命令面板同策略，不做持久化）。
class _RecentSearchQueriesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => [];

  void commit(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    state =
        <String>[
          trimmed,
          ...state.where((item) => item != trimmed),
        ].take(8).toList();
  }
}

final _recentSearchQueriesProvider =
    NotifierProvider<_RecentSearchQueriesNotifier, List<String>>(
      _RecentSearchQueriesNotifier.new,
    );

class _MobileSearchPageState extends ConsumerState<MobileSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commitRecent(String query) {
    ref.read(_recentSearchQueriesProvider.notifier).commit(query);
  }

  void _openRoute(String route) {
    _commitRecent(_controller.text);
    if (!mounted) {
      return;
    }
    context.pop();
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider);
    return Scaffold(
      backgroundColor: const Color(0xE60A0F0E),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SearchHeader(
              controller: _controller,
              focusNode: _focusNode,
              onClose: () => context.pop(),
              onChanged:
                  (value) =>
                      ref.read(searchQueryProvider.notifier).updateQuery(value),
              onSubmitted: (_) => _commitRecent(_controller.text),
              onCleared: () {
                _controller.clear();
                ref.read(searchQueryProvider.notifier).clear();
              },
            ),
            Expanded(
              child:
                  query.trim().isEmpty
                      ? _buildIdle(l10n)
                      : _buildResults(l10n, results),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdle(AppLocalizations l10n) {
    final recent = ref.watch(_recentSearchQueriesProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        _Eyebrow(l10n.searchScopesTitle.toUpperCase()),
        const SizedBox(height: 13),
        _ScopeGrid(
          onScopeSelected: (label) {
            // 样例行为：范围格即快捷查询填充，聚焦继续输入。
            _controller.text = label;
            ref.read(searchQueryProvider.notifier).updateQuery(label);
            _focusNode.requestFocus();
          },
        ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 28),
          _Eyebrow(l10n.searchRecentQueries.toUpperCase()),
          const SizedBox(height: 5),
          for (final item in recent)
            _RecentRow(
              item: item,
              onTap: () {
                _controller.text = item;
                ref.read(searchQueryProvider.notifier).updateQuery(item);
              },
            ),
        ],
      ],
    );
  }

  List<Widget> _commandsSection(AppLocalizations l10n, String query) {
    final commands = <(OmniIconsData, String, VoidCallback)>[
      (OmniIcons.home, l10n.searchCommandHome, () => _openRoute('/portal')),
      (
        OmniIcons.library,
        l10n.searchCommandLibrary,
        () => _openRoute('/library'),
      ),
      (OmniIcons.book, l10n.searchCommandReader, () => _openRoute('/reader')),
      (OmniIcons.folder, l10n.searchCommandFiles, () => _openRoute('/files')),
      (OmniIcons.image, l10n.searchCommandPhotos, () => _openRoute('/photos')),
      (OmniIcons.film, l10n.searchCommandMovies, () => _openRoute('/video')),
      (OmniIcons.music, l10n.searchCommandMusic, () => _openRoute('/music')),
    ];
    final lower = query.toLowerCase();
    final filtered =
        commands
            .where((command) => command.$2.toLowerCase().contains(lower))
            .toList();
    return [
      for (final command in filtered)
        _CommandRow(icon: command.$1, label: command.$2, onTap: command.$3),
    ];
  }

  Widget _buildResults(
    AppLocalizations l10n,
    AsyncValue<List<SearchResult>> results,
  ) {
    final query = ref.watch(searchQueryProvider);
    final commandRows = _commandsSection(l10n, query);
    return results.when(
      loading:
          () => ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: const [
              _SkeletonRow(),
              SizedBox(height: 8),
              _SkeletonRow(),
              SizedBox(height: 8),
              _SkeletonRow(),
            ],
          ),
      error:
          (_, _) => Center(
            child: EnvEmptyState(
              icon: OmniIcons.search,
              title: l10n.searchLoadFailed,
              message: l10n.searchEmptyMessage,
              actionLabel: l10n.coreRetry,
              onAction: () => ref.invalidate(searchResultsProvider),
            ),
          ),
      data: (all) {
        final items = all;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _Eyebrow(l10n.searchResultCount(items.length + commandRows.length)),
            if (commandRows.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...commandRows,
              const SizedBox(height: 8),
            ] else
              const SizedBox(height: 13),
            if (items.isEmpty && commandRows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: EnvEmptyState(
                  icon: OmniIcons.search,
                  title: l10n.searchEmptyTitle,
                  message: l10n.searchEmptyMessage,
                ),
              ),
            for (final item in items)
              _SearchResultRow(
                item: item,
                onTap: () => _openRoute(_routeFor(item)),
              ),
          ],
        );
      },
    );
  }

  String _routeFor(SearchResult item) {
    return switch (item.type) {
      'file' => '/files',
      'book' => '/reader/items/${item.id}',
      // 分集进剧集详情选集；禁止用分集 id 打开影片详情。
      'video' => movieDetailRouteFromIds(
        videoItemId: item.id,
        seriesId: item.seriesId,
      ),
      'photo' => '/photos/${item.id}',
      'music' => '/music',
      _ => '/library',
    };
  }
}

/// 眉标（10px / 1.65 / 58% 墨色）。
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0x94F6F6F2),
        // ignore: font_size_whitelist
        fontSize: 10,
        letterSpacing: 1.65,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// 头部：返回钮 + 48 高 r16 输入胶囊。
class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.focusNode,
    required this.onClose,
    required this.onChanged,
    required this.onSubmitted,
    required this.onCleared,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClose;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 90,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 7),
        child: Center(
          child: Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: onClose,
                icon: const OmniIcon(
                  icon: OmniIcons.arrow,
                  size: 21,
                  color: MobileEnvColors.ink,
                ),
                style: IconButton.styleFrom(
                  foregroundColor: MobileEnvColors.ink,
                  minimumSize: const Size.square(48),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: BoxDecoration(
                    color: const Color(0x13FFFFFF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x1AFFFFFF)),
                  ),
                  child: Row(
                    children: [
                      const OmniIcon(
                        icon: OmniIcons.search,
                        size: 19,
                        color: Color(0x9EF6F6F2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          keyboardType: TextInputType.webSearch,
                          textInputAction: TextInputAction.search,
                          style: const TextStyle(
                            color: MobileEnvColors.ink,
                            // ignore: font_size_whitelist
                            fontSize: 14,
                          ),
                          onChanged: onChanged,
                          onSubmitted: onSubmitted,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isCollapsed: true,
                            hintStyle: const TextStyle(
                              color: Color(0x5CFFFFFF),
                              // ignore: font_size_whitelist
                              fontSize: 14,
                            ),
                            hintText: l10n.searchMobilePlaceholder,
                          ),
                        ),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, _) {
                          if (value.text.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return IconButton(
                            tooltip: l10n.coreClear,
                            onPressed: onCleared,
                            icon: const OmniIcon(
                              icon: OmniIcons.close,
                              size: 18,
                              color: Color(0x9EF6F6F2),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      // 样例 label 尾部键帽（桌面快捷键提示，移动端弱化）。
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x1FFFFFFF),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Text(
                          '⌘K',
                          style: TextStyle(
                            color: Color(0x9EF6F6F2),
                            // ignore: font_size_whitelist
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
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

/// 最近搜索行（51 高 / 发丝线 / 右上箭头）。
class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.item, required this.onTap});

  final String item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 51),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x12FFFFFF))),
        ),
        child: Row(
          children: [
            const OmniIcon(
              icon: OmniIcons.search,
              size: 18,
              color: Color(0x9EF6F6F2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MobileEnvColors.ink,
                  // ignore: font_size_whitelist
                  fontSize: 12,
                ),
              ),
            ),
            Transform.rotate(
              angle: math.pi / 4,
              child: const OmniIcon(
                icon: OmniIcons.arrow,
                size: 17,
                color: Color(0x9EF6F6F2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 命令行：36 r11 图标盒 + 标题 + chevron。
class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final OmniIconsData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0x1AD5F17D),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Center(
                child: OmniIcon(
                  icon: icon,
                  size: 18,
                  color: MobileEnvColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MobileEnvColors.ink,
                  // ignore: font_size_whitelist
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const OmniIcon(
              icon: OmniIcons.chevron,
              size: 17,
              color: Color(0x9EF6F6F2),
            ),
          ],
        ),
      ),
    );
  }
}

/// 结果行（69 高 / 42 r13 图标盒 / 发丝线）。
class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({required this.item, required this.onTap});

  final SearchResult item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final IconData icon = switch (item.type) {
      'video' => Icons.movie_outlined,
      'music' => Icons.music_note_outlined,
      'book' => Icons.menu_book_outlined,
      'photo' => Icons.image_outlined,
      'file' => Icons.folder_outlined,
      _ => Icons.search_rounded,
    };
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 69),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: MobileEnvColors.line13)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0x14D5F17D),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 19, color: MobileEnvColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MobileEnvColors.ink,
                      // ignore: font_size_whitelist
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.subtitle.isNotEmpty)
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // ignore: font_size_whitelist
                      style: TextStyle(
                        color: const Color(0x9EF6F6F2),
                        // ignore: font_size_whitelist
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            ),
            const OmniIcon(
              icon: OmniIcons.chevron,
              size: 18,
              color: Color(0x9EF6F6F2),
            ),
          ],
        ),
      ),
    );
  }
}

/// 范围九宫格（3 列 / 84 高 / 17 圆角）；点击回填查询文本。
class _ScopeGrid extends StatelessWidget {
  const _ScopeGrid({required this.onScopeSelected});

  final ValueChanged<String> onScopeSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scopes = <(String, OmniIconsData)>[
      (l10n.portalDockPhotos, OmniIcons.image),
      (l10n.portalDockMovies, OmniIcons.film),
      (l10n.mobileNavMusic, OmniIcons.music),
      (l10n.searchGroupBook, OmniIcons.book),
      (l10n.searchGroupFile, OmniIcons.folder),
      (l10n.searchGroupCommand, OmniIcons.sparkle),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 6 : 3;
        final rows = (scopes.length / columns).ceil();
        final height = rows * 84.0 + (rows - 1) * 9.0;
        return SizedBox(
          height: height,
          child: GridView.count(
            crossAxisCount: columns,
            mainAxisSpacing: 9,
            crossAxisSpacing: 9,
            childAspectRatio: 1.55,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final (label, icon) in scopes)
                InkWell(
                  onTap: () => onScopeSelected(label),
                  borderRadius: BorderRadius.circular(17),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0x0CFFFFFF),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: const Color(0x14FFFFFF)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OmniIcon(
                          icon: icon,
                          size: 22,
                          color: MobileEnvColors.accent,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          label,
                          // ignore: font_size_whitelist
                          style: TextStyle(
                            color: const Color(0x9EF6F6F2),
                            // ignore: font_size_whitelist
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0x0CFFFFFF),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}
