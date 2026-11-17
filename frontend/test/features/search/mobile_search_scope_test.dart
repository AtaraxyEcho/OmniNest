// 全局搜索覆盖层的内容档行为回归：切档保留查询词、只查选中的档、
// 单档失败不吞掉其它档结果、结果行走来源自带的直达路由、
// 页面带着未完成请求退出不得回写、返回一次即离开。
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/search/scoped_search_registry.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/search/presentation/pages/mobile_search_page.dart';

class _FakeSource extends ScopedSearchSource {
  _FakeSource(this.scope, {this.label = '命中', this.fails = false});

  @override
  final ScopedSearchId scope;
  final String label;
  final bool fails;

  /// 每次取数记录的查询词，用于断言「只查选中的档」。
  final List<String> queries = <String>[];

  @override
  Future<List<ScopedSearchResult>> search(
    Ref ref,
    String query, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    queries.add(query);
    if (fails) {
      throw const FormatException('该档取数失败');
    }
    return <ScopedSearchResult>[
      ScopedSearchResult(
        title: label,
        subtitle: '副题',
        detailRoute: '/target',
        scope: scope,
      ),
    ];
  }
}

/// 防抖窗口：300ms，测试留 400ms 余量。
const Duration _debounceWindow = Duration(milliseconds: 400);

Future<GoRouter> _pumpSearch(
  WidgetTester tester, {
  required List<ScopedSearchSource> sources,
  ScopedSearchId? initialScope,
}) async {
  ScopedSearchRegistry.clearForTest();
  for (final source in sources) {
    ScopedSearchRegistry.register(source);
  }
  addTearDown(ScopedSearchRegistry.clearForTest);

  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/portal',
    routes: <RouteBase>[
      GoRoute(
        path: '/portal',
        builder: (context, state) => const Scaffold(body: Text('起点页')),
      ),
      GoRoute(
        path: '/search',
        builder:
            (context, state) => MobileSearchPage(initialScope: initialScope),
      ),
      GoRoute(
        path: '/target',
        builder: (context, state) => const Scaffold(body: Text('目标页')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('zh'),
        theme: OmniNestTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  // 从壳层入口进入覆盖层（push 保留返回栈）。
  router.push('/search');
  await tester.pump();
  return router;
}

Future<void> _typeQuery(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).first, query);
  await tester.pump(_debounceWindow);
  await tester.pump();
}

void main() {
  testWidgets('切档只查选中的档，且不把档名写进输入框', (tester) async {
    final video = _FakeSource(ScopedSearchId.video, label: '影片命中');
    final photo = _FakeSource(ScopedSearchId.photo, label: '照片命中');
    await _pumpSearch(tester, sources: <ScopedSearchSource>[video, photo]);

    await tester.tap(find.text('媒体'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      '',
      reason: '样例把档名当查询词回填；这里切档不覆盖输入',
    );

    await _typeQuery(tester, 'mirage');

    expect(find.text('影片命中'), findsOneWidget);
    expect(find.text('照片命中'), findsNothing);
    expect(video.queries, contains('mirage'));
    expect(photo.queries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切回全部档后各已登记档合并', (tester) async {
    final video = _FakeSource(ScopedSearchId.video, label: '影片命中');
    final photo = _FakeSource(ScopedSearchId.photo, label: '照片命中');
    await _pumpSearch(tester, sources: <ScopedSearchSource>[video, photo]);

    await tester.tap(find.text('媒体'));
    await tester.pump();
    await tester.tap(find.text('全部'));
    await tester.pump();

    await _typeQuery(tester, 'mirage');

    expect(find.text('影片命中'), findsOneWidget);
    expect(find.text('照片命中'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('预选档进入即只查该档', (tester) async {
    final video = _FakeSource(ScopedSearchId.video, label: '影片命中');
    final photo = _FakeSource(ScopedSearchId.photo, label: '照片命中', fails: true);
    await _pumpSearch(
      tester,
      sources: <ScopedSearchSource>[video, photo],
      initialScope: ScopedSearchId.video,
    );

    await _typeQuery(tester, 'dune');

    expect(find.text('影片命中'), findsOneWidget);
    expect(find.textContaining('搜索暂时不可用'), findsNothing);
    expect(photo.queries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单档失败只降级该档，不吞掉其它档结果', (tester) async {
    final video = _FakeSource(ScopedSearchId.video, label: '影片命中');
    final photo = _FakeSource(ScopedSearchId.photo, label: '照片命中', fails: true);
    await _pumpSearch(tester, sources: <ScopedSearchSource>[video, photo]);

    await _typeQuery(tester, 'mirage');

    expect(find.text('影片命中'), findsOneWidget);
    expect(find.textContaining('搜索暂时不可用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未登记的档不占范围格', (tester) async {
    await _pumpSearch(
      tester,
      sources: <ScopedSearchSource>[
        _FakeSource(ScopedSearchId.video, label: '影片命中'),
      ],
    );

    expect(find.text('媒体'), findsOneWidget);
    expect(find.text('照片'), findsNothing);
    expect(find.text('书籍'), findsNothing);
    // 第六格是复位档「全部」，不是样例里没有取数来源的「命令」。
    expect(find.text('全部'), findsOneWidget);
  });

  testWidgets('结果行走来源自带的直达路由', (tester) async {
    await _pumpSearch(
      tester,
      sources: <ScopedSearchSource>[
        _FakeSource(ScopedSearchId.video, label: '影片命中'),
      ],
    );

    await _typeQuery(tester, 'mirage');
    await tester.tap(find.text('影片命中'));
    await tester.pumpAndSettle();

    expect(find.text('目标页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('超长输入在输入侧就被限住，框里文本即实际检索文本', (tester) async {
    final video = _FakeSource(ScopedSearchId.video, label: '影片命中');
    await _pumpSearch(tester, sources: <ScopedSearchSource>[video]);

    await tester.enterText(
      find.byType(TextField).first,
      'a' * (ScopedSearchLimits.maxQueryLength + 50),
    );
    await tester.pump(_debounceWindow);

    // 不是"发出去再被服务端拒掉"：用户看到的和被打出去的必须同一条。
    expect(
      tester
          .widget<TextField>(find.byType(TextField).first)
          .controller!
          .text
          .length,
      ScopedSearchLimits.maxQueryLength,
    );
    expect(video.queries, <String>['a' * ScopedSearchLimits.maxQueryLength]);
  });

  testWidgets('带未完成请求退出页面后无过期回写', (tester) async {
    await _pumpSearch(
      tester,
      sources: <ScopedSearchSource>[
        _FakeSource(ScopedSearchId.video, label: '影片命中'),
      ],
    );

    await tester.enterText(find.byType(TextField).first, 'partial');
    // 不等防抖与响应返回就离开页面。
    await tester.tap(find.byType(IconButton).first);
    await tester.pumpAndSettle();
    await tester.pump(_debounceWindow);

    expect(find.text('起点页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
