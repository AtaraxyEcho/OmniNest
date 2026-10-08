import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/search/scoped_search_registry.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/infinite_scroll.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/core/widgets/top_bar_search_focus.dart';
import 'package:omninest/features/search/application/scoped_search_controller.dart';
import 'package:omninest/features/search/application/search_controller.dart';

/// 全局搜索的移动端全屏覆盖层（样例 search-overlay 逐值复刻）。
///
/// 头部 48 高 r16 输入胶囊；空态 = SEARCH ACROSS OMNINEST 眉标 + 3 列
/// 范围格 + 最近搜索行；结果行 42 r13 强调色图标盒。
///
/// 有意偏离样例两处：样例是 `position: fixed` 的浮层，这里做成路由页以取得
/// 干净的返回栈与深链语义；样例底是 blur 34，这里不接 backdrop filter——
/// 底层已是近乎实底的覆盖色，加模糊只增帧成本不改观感。
class MobileSearchPage extends ConsumerStatefulWidget {
  const MobileSearchPage({this.initialScope, super.key});

  /// 进入时预选的内容档；为空即「全部」。由路由的 `scope` 查询参数传入。
  final ScopedSearchId? initialScope;

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

class _MobileSearchPageState extends ConsumerState<MobileSearchPage>
    with RouteTopAware {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  TopBarSearchFocusHandle? _searchFocusHandle;

  @override
  void initState() {
    super.initState();
    // 入口预选档在首帧后再写 provider：Riverpod 禁止在 initState 改 provider。
    // 进入时查询词为空、不会发请求，因此这一次延后不产生多余的整档查询。
    final initialScope = widget.initialScope;
    if (initialScope != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(scopedSearchSelectionProvider.notifier).select(initialScope);
        }
      });
    }
    // 撤销模块页内搜索条后，Ctrl/Cmd+F 必须有新目标，否则键盘路径静默
    // 回落到浏览器原生查找；栈顶自检避免下层页面抢焦点。
    _searchFocusHandle = TopBarSearchFocusRegistry.instance.register(
      TopBarSearchFocusEntry(
        focus: _focusNode.requestFocus,
        isActive: () => mounted && isRouteTop,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchFocusHandle?.dispose();
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
    final results = ref.watch(scopedSearchProvider);
    return Scaffold(
      backgroundColor: context.env.searchOverlayBg,
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
          selected: ref.watch(scopedSearchSelectionProvider)?.scope,
          onScopeSelected: (scope) {
            // 范围格是切档，不是把档名当查询词填进输入框：已输入的内容保留。
            ref.read(scopedSearchSelectionProvider.notifier).select(scope);
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
    AsyncValue<ScopedSearchBatch> results,
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
              onAction: () => ref.invalidate(scopedSearchProvider),
            ),
          ),
      data: (batch) {
        final items = batch.results;
        final unavailable = batch.groups.where((group) => group.unavailable);
        return InfiniteScrollTrigger(
          enabled: batch.hasMore,
          onLoadMore: () => ref.read(scopedSearchProvider.notifier).loadMore(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _Eyebrow(
                l10n.searchResultCount(items.length + commandRows.length),
              ),
              if (commandRows.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...commandRows,
                const SizedBox(height: 8),
              ] else
                const SizedBox(height: 13),
              if (items.isEmpty && commandRows.isEmpty && unavailable.isEmpty)
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
                  result: item,
                  onTap: () => _openRoute(item.detailRoute),
                ),
              // 单档失败只降级该档：其它档的结果仍然显示，只补一行提示。
              for (final group in unavailable)
                _UnavailableScopeRow(
                  label: _scopeLabelOf(l10n, group.scope),
                  message: l10n.searchLoadFailed,
                ),
            ],
          ),
        );
      },
    );
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
                icon: OmniIcon(
                  icon: OmniIcons.arrow,
                  size: 21,
                  color: context.env.ink,
                ),
                style: IconButton.styleFrom(
                  foregroundColor: context.env.ink,
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
                          // 与服务端关键词上限同口径：限在输入侧，框里的文本才等于真正被检索
                          // 的文本，超长粘贴不会变成一次"该档不可用"。
                          inputFormatters: <TextInputFormatter>[
                            LengthLimitingTextInputFormatter(
                              ScopedSearchLimits.maxQueryLength,
                            ),
                          ],
                          style: TextStyle(
                            color: context.env.ink,
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
                style: TextStyle(
                  color: context.env.ink,
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
                  color: context.env.accentInk,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.env.ink,
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
  const _SearchResultRow({required this.result, required this.onTap});

  final ScopedSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final IconData icon = switch (result.scope) {
      ScopedSearchId.video => Icons.movie_outlined,
      ScopedSearchId.music => Icons.music_note_outlined,
      ScopedSearchId.book => Icons.menu_book_outlined,
      ScopedSearchId.photo => Icons.image_outlined,
      ScopedSearchId.file => Icons.folder_outlined,
    };
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 69),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.env.line13)),
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
              child: Icon(icon, size: 19, color: context.env.accentInk),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.env.ink,
                      // ignore: font_size_whitelist
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (result.subtitle?.isNotEmpty ?? false)
                    Text(
                      result.subtitle!,
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

/// 档位标签：与范围格共用同一批既有文案，不新增 ARB 键。
String _scopeLabelOf(AppLocalizations l10n, ScopedSearchId scope) {
  return switch (scope) {
    ScopedSearchId.video => l10n.portalDockMovies,
    ScopedSearchId.photo => l10n.portalDockPhotos,
    ScopedSearchId.music => l10n.mobileNavMusic,
    ScopedSearchId.book => l10n.searchGroupBook,
    ScopedSearchId.file => l10n.searchGroupFile,
  };
}

/// 单档未能返回的行内提示：只降级该档，其它档结果照常显示。
class _UnavailableScopeRow extends StatelessWidget {
  const _UnavailableScopeRow({required this.label, required this.message});

  final String label;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          const OmniIcon(
            icon: OmniIcons.cloud,
            size: 16,
            color: Color(0x9EF6F6F2),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '$label · $message',
              style: TextStyle(
                color: context.env.inkMuted,
                // ignore: font_size_whitelist
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 范围九宫格（3 列 / 84 高 / 17 圆角）；点击切档并保留已输入的查询词。
class _ScopeGrid extends StatelessWidget {
  const _ScopeGrid({required this.selected, required this.onScopeSelected});

  final ScopedSearchId? selected;
  final ValueChanged<ScopedSearchId?> onScopeSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 只列已登记来源的档：未登记的档点了必然空，不摆空位。
    // 第六格样例是「命令」，它没有取数来源，这里换成「全部」用于复位档位，
    // 导航命令行仍随「全部」显示。
    final cells = <(ScopedSearchId?, String, OmniIconsData)>[
      for (final entry in <(ScopedSearchId, String, OmniIconsData)>[
        (ScopedSearchId.video, l10n.portalDockMovies, OmniIcons.film),
        (ScopedSearchId.photo, l10n.portalDockPhotos, OmniIcons.image),
        (ScopedSearchId.music, l10n.mobileNavMusic, OmniIcons.music),
        (ScopedSearchId.book, l10n.searchGroupBook, OmniIcons.book),
        (ScopedSearchId.file, l10n.searchGroupFile, OmniIcons.folder),
      ])
        if (ScopedSearchRegistry.lookup(entry.$1) != null) entry,
      (null, l10n.videoRedesignFilterAll, OmniIcons.sparkle),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 6 : 3;
        final rows = (cells.length / columns).ceil();
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
              for (final (scope, label, icon) in cells)
                InkWell(
                  onTap: () => onScopeSelected(scope),
                  borderRadius: BorderRadius.circular(17),
                  child: Container(
                    decoration: BoxDecoration(
                      color:
                          scope == selected
                              ? context.env.accentInk.withValues(alpha: 0.10)
                              : const Color(0x0CFFFFFF),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color:
                            scope == selected
                                ? context.env.accentInk.withValues(alpha: 0.38)
                                : const Color(0x14FFFFFF),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OmniIcon(
                          icon: icon,
                          size: 22,
                          color: context.env.accentInk,
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
