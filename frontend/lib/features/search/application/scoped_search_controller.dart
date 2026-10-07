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
  });

  final ScopedSearchId scope;
  final List<ScopedSearchResult> results;

  /// 该来源本次未能返回。只降级本档并在界面上给一行提示，
  /// 不吞掉其它档的结果，也不把整次搜索判失败。
  final bool unavailable;

  bool get hasMore => results.length >= ScopedSearchLimits.perSource;
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

  List<ScopedSearchResult> get results {
    final merged = <ScopedSearchResult>[];
    for (final group in groups) {
      merged.addAll(group.results);
      if (merged.length >= ScopedSearchLimits.total) {
        break;
      }
    }
    return merged.length > ScopedSearchLimits.total
        ? merged.sublist(0, ScopedSearchLimits.total)
        : merged;
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
    ref.onDispose(() => _cancelToken?.cancel());
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
    final current = state.asData?.value;
    final query = ref.read(searchQueryProvider).trim();
    if (current == null ||
        query.isEmpty ||
        !current.hasMore ||
        current.query != query) {
      return;
    }
    final next = await _run(
      query,
      ref.read(scopedSearchSelectionProvider)?.scope,
      page: current.page + 1,
      replace: false,
    );
    if (next == null) {
      return;
    }
    state = AsyncData(next);
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
    final targets = _targets(scope);

    // 防抖：连续输入只保留最后一次请求，旧响应靠 generation 丢弃。
    await Future<void>.delayed(_debounce);
    if (generation != _generation || cancelToken.isCancelled) {
      return null;
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
      return ScopedSearchGroup(scope: source.scope, results: results);
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

  List<ScopedSearchGroup> _merge(
    List<ScopedSearchGroup> previous,
    List<ScopedSearchGroup> settled,
  ) {
    if (previous.isEmpty) {
      return settled;
    }
    return <ScopedSearchGroup>[
      for (final group in settled)
        ScopedSearchGroup(
          scope: group.scope,
          results: <ScopedSearchResult>[
            ...(previous
                    .where((item) => item.scope == group.scope)
                    .firstOrNull
                    ?.results ??
                const <ScopedSearchResult>[]),
            ...group.results,
          ],
          unavailable: group.unavailable,
        ),
    ];
  }
}
