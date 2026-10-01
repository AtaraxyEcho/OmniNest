import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/workstation_portal_link.dart';

void main() {
  // 与各模块工位顶栏一致的承载环境：l10n + 主题 + 路由栈。
  Future<void> pumpLink(WidgetTester tester, {VoidCallback? onTap}) async {
    Widget linkPage(String marker) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [WorkstationPortalLink(onTap: onTap), Text(marker)],
        ),
      ),
    );
    final router = GoRouter(
      initialLocation: '/work',
      routes: [
        GoRoute(path: '/portal', builder: (_, _) => const Scaffold()),
        GoRoute(path: '/work', builder: (_, _) => linkPage('WORK')),
        GoRoute(path: '/pushed', builder: (_, _) => linkPage('PUSHED')),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
      ),
    );
    await tester.pump();
  }

  testWidgets('呈现统一的箭头 + PORTAL 等宽标签', (tester) async {
    await pumpLink(tester);

    expect(find.text('PORTAL'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('缺省行为：无栈可弹时回 Portal', (tester) async {
    await pumpLink(tester);

    await tester.tap(find.text('PORTAL'));
    await tester.pumpAndSettle();

    expect(find.text('PORTAL'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('缺省行为：栈可弹时 pop 回来源页而非回 Portal', (tester) async {
    await pumpLink(tester);
    tester.element(find.text('WORK')).push('/pushed');
    await tester.pumpAndSettle();
    expect(find.text('PUSHED'), findsOneWidget);

    await tester.tap(find.text('PORTAL'));
    await tester.pumpAndSettle();

    // pop 回来源页：仍能看到来源页标记，而不是落到空的 /portal。
    expect(find.text('WORK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('显式 onTap 优先于缺省导航', (tester) async {
    var tapped = 0;
    await pumpLink(tester, onTap: () => tapped++);

    await tester.tap(find.text('PORTAL'));
    await tester.pump();

    expect(tapped, 1);
    // 显式回调不触发路由跳转，链接仍在当前页。
    expect(find.text('WORK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
