import 'package:flutter/material.dart';
import 'package:omninest/core/widgets/workstation_pagination_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';

void main() {
  Widget host({
    required int currentPage,
    required int totalPages,
    required int totalElements,
    required int rowsPerPage,
    ValueChanged<int>? onPageChanged,
    ValueChanged<int>? onRowsPerPageChanged,
  }) {
    return MaterialApp(
      theme: OmniNestTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: WorkstationPaginationBar(
          currentPage: currentPage,
          totalPages: totalPages,
          totalElements: totalElements,
          rowsPerPage: rowsPerPage,
          onPageChanged: onPageChanged ?? (_) {},
          onRowsPerPageChanged: onRowsPerPageChanged ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('渲染总数与当前范围并回调页码切换', (tester) async {
    var tappedPage = -1;
    await tester.pumpWidget(
      host(
        currentPage: 0,
        totalPages: 3,
        totalElements: 25,
        rowsPerPage: 10,
        onPageChanged: (page) => tappedPage = page,
      ),
    );

    expect(find.text('共 25 条'), findsOneWidget);
    expect(find.text('第 1-10 条'), findsOneWidget);
    // 总页数 ≤7：页码全量展示。
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(tappedPage, 1, reason: '页码 chip 回调 0 基页码');
  });

  testWidgets('总页数超过 7 时折叠省略号且跳页生效', (tester) async {
    var tappedPage = -1;
    await tester.pumpWidget(
      host(
        currentPage: 0,
        totalPages: 12,
        totalElements: 120,
        rowsPerPage: 10,
        onPageChanged: (page) => tappedPage = page,
      ),
    );

    expect(find.text('…'), findsOneWidget, reason: '12 页折叠出省略号');
    // 总页数 >5 出现跳页输入框。
    await tester.enterText(find.byType(TextField), '9');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tappedPage, 8, reason: '跳至第 9 页回调 0 基页码 8');
  });

  testWidgets('首页与上页在第一页禁用', (tester) async {
    await tester.pumpWidget(
      host(currentPage: 0, totalPages: 5, totalElements: 50, rowsPerPage: 10),
    );

    final firstButton = find.byIcon(Icons.first_page_rounded);
    final prevButton = find.byIcon(Icons.chevron_left_rounded);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(of: firstButton, matching: find.byType(IconButton)),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(of: prevButton, matching: find.byType(IconButton)),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('计数组与翻页组整体靠左，不两端铺开', (tester) async {
    await tester.pumpWidget(
      host(currentPage: 0, totalPages: 12, totalElements: 120, rowsPerPage: 10),
    );

    // 计数组与翻页组同一左簇：布局契约为 start，禁止回到两端铺开。
    final wrap = tester.widget<Wrap>(
      find.descendant(
        of: find.byType(WorkstationPaginationBar),
        matching: find.byType(Wrap),
      ),
    );
    expect(wrap.alignment, WrapAlignment.start);
  });
}
