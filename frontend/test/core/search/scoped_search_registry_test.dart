// 全局搜索内容档注册表：登记、查找、顺序与幂等替换。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/search/scoped_search_registry.dart';
import 'package:omninest/core/search/scoped_search_source.dart';

class _NamedSource extends ScopedSearchSource {
  _NamedSource(this.scope);

  @override
  final ScopedSearchId scope;

  @override
  Future<List<ScopedSearchResult>> search(
    Ref ref,
    String query, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    return const <ScopedSearchResult>[];
  }
}

void main() {
  setUp(ScopedSearchRegistry.clearForTest);
  tearDown(ScopedSearchRegistry.clearForTest);

  test('未登记时不返回来源，查找为空', () {
    expect(ScopedSearchRegistry.sources, isEmpty);
    expect(ScopedSearchRegistry.lookup(ScopedSearchId.video), isNull);
  });

  test('来源按内容档声明顺序返回，与登记先后无关', () {
    ScopedSearchRegistry.register(_NamedSource(ScopedSearchId.photo));
    ScopedSearchRegistry.register(_NamedSource(ScopedSearchId.video));

    expect(
      ScopedSearchRegistry.sources.map((source) => source.scope),
      <ScopedSearchId>[ScopedSearchId.video, ScopedSearchId.photo],
    );
  });

  test('同档重复登记替换旧实现，不叠加两份', () {
    final first = _NamedSource(ScopedSearchId.video);
    final second = _NamedSource(ScopedSearchId.video);
    ScopedSearchRegistry.register(first);
    ScopedSearchRegistry.register(second);

    expect(ScopedSearchRegistry.lookup(ScopedSearchId.video), same(second));
    expect(ScopedSearchRegistry.sources, hasLength(1));
  });

  test('上限按档截断，单档 20 条', () {
    expect(ScopedSearchLimits.perSource, 20);
    expect(ScopedSearchLimits.total, 60);
    expect(ScopedSearchLimits.total, greaterThan(ScopedSearchLimits.perSource));
  });
}
