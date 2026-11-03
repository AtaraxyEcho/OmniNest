import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/search/scoped_search_registry.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/search/application/search_controller.dart';

/// 用户在覆盖层里显式选定的内容档。
///
/// 包一层是为了区分「还没选」与「选了全部」：预选档由入口传入，若直接用
/// `null` 表示全部，用户主动点「全部」时就会盖不掉入口带来的预选。
class ScopedSearchSelection {
  const ScopedSearchSelection(this.scope);

  final ScopedSearchId? scope;
}

final scopedSearchSelectionProvider = NotifierProvider.autoDispose<
  ScopedSearchSelectionNotifier,
  ScopedSearchSelection?
>(ScopedSearchSelectionNotifier.new);

class ScopedSearchSelectionNotifier extends Notifier<ScopedSearchSelection?> {
  @override
  ScopedSearchSelection? build() => null;

  /// 切换档位保留已输入的查询词：范围格不是「把档位名塞进输入框」。
  void select(ScopedSearchId? scope) => state = ScopedSearchSelection(scope);
}

/// 一个内容档的本次结果。
class ScopedSearchGroup {
  const ScopedSearchGroup({
    required this.scope,
    required this.results,
    this.unavailable = false,
    this.hasMore = false,
  });

  final ScopedSearchId scope;
  final List<ScopedSearchResult> results;

  /// 该来源本次未能返回。只降级本档并在界面上给一行提示，
  /// 不吞掉其它档的结果，也不把整次搜索判失败。
  final bool unavailable;

  /// 本页是否还有下一页。
  ///
  /// 必须由“本页返回条数”在取数时判定并固化：用合并后的总长度推导会让
  /// “首屏 20 条 + 次页 0 条”仍然满足 `>= perSource`，用户每次滚到底都会再发一页，
  /// 形成永不停止的翻页请求。
  final bool hasMore;
}

/// 一次查询的结果批次。
class ScopedSearchBatch {
  const ScopedSearchBatch({
    required this.groups,
    required this.page,
    required this.query,
  });

  final List<ScopedSearchGroup> groups;
  final int page;

  /// 批次对应的查询词，用于加载更多时丢弃已过期的翻页。
  final String query;

  /// 扁平化的“全部”结果。
  ///
  /// 截断上限随已加载页数增长：固定 60 条会让第 1 页之后拉回的数据对用户完全不可见，
  /// 看起来像“加载更多没有反应”。
  List<ScopedSearchResult> get results {
    final maxItems = (page + 1) * ScopedSearchLimits.total;
    final merged = <ScopedSearchResult>[];
    for (final group in groups) {
      merged.addAll(group.results);
      if (merged.length >= maxItems) {
        break;
      }
    }
    return merged.length > maxItems ? merged.sublist(0, maxItems) : merged;
  }

  bool get hasMore => groups.any((group) => group.hasMore);
}

final scopedSearchProvider = AsyncNotifierProvider.autoDispose<
  ScopedSearchController,
  ScopedSearchBatch
>(ScopedSearchController.new);

/// 覆盖层的查询状态：自持防抖、逐源并行与过期响应丢弃。
///
/// 只走首屏加加载更多（同一来源换页），与模块页自己的无限滚动互不相干。
class ScopedSearchController extends AsyncNotifier<ScopedSearchBatch> {
  static const Duration _debounce = Duration(milliseconds: 300);

  int _generation = 0;
  bool _isLoadingMore = false;
  CancelToken? _cancelToken;
  ScopedSearchBatch _last = const ScopedSearchBatch(
    groups: <ScopedSearchGroup>[],
    page: 0,
    query: '',
  );

  @override
  Future<ScopedSearchBatch> build() async {
    final query = ref.watch(searchQueryProvider).trim();
    final scope = ref.watch(scopedSearchSelectionProvider)?.scope;
    ref.onDispose(() {
      _generation++;
      _cancelToken?.cancel();
    });
    if (query.isEmpty) {
      _last = const ScopedSearchBatch(
        groups: <ScopedSearchGroup>[],
        page: 0,
        query: '',
      );
      return _last;
    }
    return (await _run(query, scope, page: 0, replace: true)) ?? _last;
  }

  /// 追加下一页。所有档共用同一页号，翻页结果按档合并。
  Future<void> loadMore() async {
    // 触底会连续触发多次：没有门闩时第二次滚动会取消正在飞行的翻页请求。
    if (_isLoadingMore) {
      return;
    }
    final current = state.asData?.value;
    final query = ref.read(searchQueryProvider).trim();
    if (current == null ||
        query.isEmpty ||
        !current.hasMore ||
        current.query != query) {
      return;
    }
    _isLoadingMore = true;
    try {
      final next = await _run(
        query,
        ref.read(scopedSearchSelectionProvider)?.scope,
        page: current.page + 1,
        replace: false,
      );
      if (!ref.mounted || next == null) {
        return;
      }
      state = AsyncData(next);
    } finally {
      _isLoadingMore = false;
    }
  }

  /// 返回 `null` 表示本次结果已被更新的请求作废，调用方保留上一批。
  Future<ScopedSearchBatch?> _run(
    String query,
    ScopedSearchId? scope, {
    required int page,
    required bool replace,
  }) async {
    final generation = ++_generation;
    _cancelToken?.cancel();
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    final previous =
        replace
            ? const <ScopedSearchGroup>[]
            : (state.asData?.value.groups ?? const <ScopedSearchGroup>[]);
    final targets = _scrollTargets(scope, previous, replace);

    // 防抖只服务连续输入：翻页是显式动作，等 300ms 只会让触底加载变钝。
    if (replace) {
      await Future<void>.delayed(_debounce);
      if (generation != _generation || cancelToken.isCancelled) {
        return null;
      }
    }

    final settled = await Future.wait(<Future<ScopedSearchGroup>>[
      for (final source in targets) _collect(source, query, page, cancelToken),
    ]);

    if (generation != _generation || cancelToken.isCancelled) {
      return null;
    }
    final batch = ScopedSearchBatch(
      groups: _merge(previous, settled),
      page: page,
      query: query,
    );
    _last = batch;
    return batch;
  }

  Future<ScopedSearchGroup> _collect(
    ScopedSearchSource source,
    String query,
    int page,
    CancelToken cancelToken,
  ) async {
    try {
      final results = await source.search(
        ref,
        query,
        page: page,
        cancelToken: cancelToken,
      );
      return ScopedSearchGroup(
        scope: source.scope,
        results: results,
        hasMore: results.length >= ScopedSearchLimits.perSource,
      );
    } on Exception {
      // 主动取消的批次在 generation 检查处就被丢弃，到这里只剩真失败：
      // 只把该档标成未能返回，保留其它档结果。
      return ScopedSearchGroup(
        scope: source.scope,
        results: const <ScopedSearchResult>[],
        unavailable: true,
      );
    }
  }

  List<ScopedSearchSource> _targets(ScopedSearchId? scope) {
    if (scope == null) {
      return ScopedSearchRegistry.sources;
    }
    final source = ScopedSearchRegistry.lookup(scope);
    return source == null
        ? const <ScopedSearchSource>[]
        : <ScopedSearchSource>[source];
  }

  /// 翻页时只请求“本档还有下一页”的来源，已到底的档直接沿用上一批结果。
  List<ScopedSearchSource> _scrollTargets(
    ScopedSearchId? scope,
    List<ScopedSearchGroup> previous,
    bool replace,
  ) {
    final targets = _targets(scope);
    if (replace || previous.isEmpty) {
      return targets;
    }
    final exhausted = <ScopedSearchId>{
      for (final group in previous)
        if (!group.hasMore) group.scope,
    };
    return targets
        .where((source) => !exhausted.contains(source.scope))
        .toList();
  }

  List<ScopedSearchGroup> _merge(
    List<ScopedSearchGroup> previous,
    List<ScopedSearchGroup> settled,
  ) {
    if (previous.isEmpty) {
      return settled;
    }
    final settledByScope = <ScopedSearchId, ScopedSearchGroup>{
      for (final group in settled) group.scope: group,
    };
    final merged = <ScopedSearchGroup>[];
    for (final group in previous) {
      final fresh = settledByScope.remove(group.scope);
      if (fresh == null) {
        // 该档已无下一页，本轮没有请求它：原样保留，不能让它从结果里消失。
        merged.add(group);
        continue;
      }
      final seenRoutes = group.results.map((item) => item.detailRoute).toSet();
      merged.add(
        ScopedSearchGroup(
          scope: fresh.scope,
          results: <ScopedSearchResult>[
            ...group.results,
            ...fresh.results.where(
              (item) => !seenRoutes.contains(item.detailRoute),
            ),
          ],
          unavailable: fresh.unavailable,
          hasMore: fresh.hasMore,
        ),
      );
    }
    // 新出现（上一批尚未返回）的档追加在末尾，保持注册表顺序。
    merged.addAll(settledByScope.values);
    return merged;
  }
}
