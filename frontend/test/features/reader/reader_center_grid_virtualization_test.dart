import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_center_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_library_cards.dart';

/// 书库网格虚拟化闸门。
///
/// 判据不是"用了哪个 widget"，而是实际被构建的卡片数量：续页只追加不裁剪，
/// 300 条已加载条目必须由视口按需实例化，不能一次性挂满整棵树。
void main() {
  testWidgets('书库加载 300 条时只构建视口附近的卡片', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 860);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        readerCenterControllerProvider.overrideWith(
          () => _FixedCenterController(_stateWith300Items()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container));
    await tester.pump(const Duration(seconds: 1));

    final builtCards =
        tester.widgetList(find.byType(ReaderLibraryGridCard)).length;
    expect(builtCards, lessThan(60), reason: '300 条全部实例化说明网格没有虚拟化');

    // 滚到底仍要能拿到最后一项，防止"变懒"变成"少渲染"。
    // 卡片标题只出现在 Semantics label 中，没有 Text 节点，必须按 widget 匹配。
    final lastCard = find.byWidgetPredicate(
      (widget) =>
          widget is ReaderLibraryGridCard && widget.item.title == '书299',
    );
    // 页面里还有横向续读栏：必须显式指定书库外层滚动体，否则 drag 会落在
    // 横向 Scrollable 上，目标永远不会滚入视口。
    await tester.scrollUntilVisible(
      lastCard,
      600,
      scrollable:
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
      maxScrolls: 200,
    );
    await tester.pumpAndSettle();
    expect(lastCard, findsOneWidget);
  });
}

Widget _host(ProviderContainer container) {
  final router = GoRouter(
    initialLocation: '/reader',
    routes: [
      GoRoute(
        path: '/reader',
        builder: (context, state) => const ReaderCenterPage(),
      ),
    ],
  );
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: router,
      theme: OmniNestTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
    ),
  );
}

ReaderCenterState _stateWith300Items() {
  final items = List<ReaderItem>.generate(
    300,
    (index) => ReaderItem(
      id: 'item-$index',
      title: '书$index',
      itemType: 'EPUB',
      updatedAt: DateTime(2026, 9, 20),
    ),
    growable: false,
  );
  return ReaderCenterState(
    dashboard: ReaderDashboard.empty(),
    items: items,
    searchQuery: '',
  );
}

class _FixedCenterController extends ReaderCenterController {
  _FixedCenterController(this.initialState);

  final ReaderCenterState initialState;

  @override
  Future<ReaderCenterState> build() async => initialState;
}
