import 'package:flutter/foundation.dart';
import 'package:omninest/core/widgets/workstation_pagination_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_list_components.dart';

void main() {
  Future<void> pumpTable(
    WidgetTester tester, {
    required int rowCount,
    required void Function(String columnKey, bool ascending) onSort,
    AdminListSort? sort,
    bool withActions = true,
    Size surface = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final columns = [
      const AdminListColumn(key: 'name', label: '名称', sortable: true),
      const AdminListColumn(key: 'ip', label: 'IP'),
    ];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: AdminDataTable(
              columns: columns,
              rowCount: rowCount,
              rowCellsBuilder:
                  (context, index) => [
                    Text('row-$index'),
                    Text('10.0.0.$index'),
                  ],
              actionsBuilder:
                  withActions
                      ? (context, index) => [
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.more_vert_rounded),
                        ),
                      ]
                      : null,
              sort: sort,
              onSort: onSort,
              showIndex: true,
              indexBase: 20,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('表格渲染行与固定操作列', (tester) async {
    await pumpTable(tester, rowCount: 3, onSort: (columnKey, ascending) {});
    expect(find.text('21'), findsOneWidget, reason: '分页基数下的序号');
    expect(find.text('row-0'), findsOneWidget);
    expect(find.text('row-2'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsNWidgets(3));
  });

  testWidgets('竖屏平板宽度下固定操作列不引发布局异常', (tester) async {
    await pumpTable(
      tester,
      rowCount: 5,
      onSort: (columnKey, ascending) {},
      surface: const Size(768, 900),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('托管画布宽度下固定操作列不引发布局异常', (tester) async {
    await pumpTable(
      tester,
      rowCount: 5,
      onSort: (columnKey, ascending) {},
      surface: const Size(720, 900),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击可排序列头回调列键与方向', (tester) async {
    String? receivedKey;
    var receivedAscending = true;
    await pumpTable(
      tester,
      rowCount: 1,
      sort: const AdminListSort(columnKey: 'name', ascending: true),
      onSort: (columnKey, ascending) {
        receivedKey = columnKey;
        receivedAscending = ascending;
      },
    );
    await tester.tap(find.text('名称'));
    await tester.pump();
    expect(receivedKey, 'name');
    expect(receivedAscending, isFalse, reason: '已升序再点应变降序');
  });

  testWidgets('表头各列与序号同行横向对齐', (tester) async {
    await pumpTable(tester, rowCount: 2, onSort: (columnKey, ascending) {});
    final nameHeader = tester.getRect(find.text('名称'));
    final indexHeader = tester.getRect(find.text('序号'));
    final actionHeader = tester.getRect(find.text('操作'));
    expect(
      indexHeader.top,
      closeTo(nameHeader.top, 0.5),
      reason: '序号表头必须与列头同一行',
    );
    expect(
      actionHeader.top,
      closeTo(nameHeader.top, 0.5),
      reason: '操作表头必须与列头同一行',
    );
    expect(indexHeader.left, lessThan(nameHeader.left), reason: '序号列在数据列之前');
  });

  testWidgets('切换每页条数回调新档位', (tester) async {
    int? received;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: WorkstationPaginationBar(
              currentPage: 0,
              totalPages: 5,
              totalElements: 100,
              rowsPerPage: 20,
              onPageChanged: (_) {},
              onRowsPerPageChanged: (value) => received = value,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('每页条数'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.text('50'),
      ),
    );
    await tester.pumpAndSettle();
    expect(received, 50);
  });

  testWidgets('分页信息展示总条数与当前范围且边界禁用', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: WorkstationPaginationBar(
              currentPage: 0,
              totalPages: 12,
              totalElements: 115,
              rowsPerPage: 10,
              onPageChanged: (_) {},
              onRowsPerPageChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('共 115 条'), findsOneWidget);
    expect(find.text('第 1-10 条'), findsOneWidget);
    expect(find.text('…'), findsOneWidget, reason: '12 页需折叠为 1 2 … 12');

    // 单行布局：计数文本与页码 chip 垂直中心严格对齐（同一行基线）。
    final countCenter = tester.getCenter(find.text('共 115 条')).dy;
    final chipCenter = tester.getCenter(find.text('2')).dy;
    expect(
      (countCenter - chipCenter).abs(),
      lessThan(1),
      reason: '计数与页码必须同行垂直居中对齐',
    );

    // 选中页码 chip：surfaceContainerHighest 底 + outline 边框 + w700。
    final scheme = OmniNestTheme.light().colorScheme;
    final selectedChip = tester.widget<Container>(
      find.ancestor(of: find.text('1'), matching: find.byType(Container)).first,
    );
    final decoration = selectedChip.decoration as BoxDecoration;
    expect(decoration.color, scheme.surfaceContainerHighest);
    expect(decoration.border?.top.width, 1);
    expect(selectedChip.constraints?.minHeight, 44, reason: '触控密度 44px');
    final selectedText = tester.widget<Text>(find.text('1'));
    expect(selectedText.style?.fontWeight, FontWeight.w700);
    expect(selectedText.style?.fontFamily, AppTypography.monoFamily);

    // 未选中 chip：透明底、无边框。
    final normalChip = tester.widget<Container>(
      find.ancestor(of: find.text('2'), matching: find.byType(Container)).first,
    );
    final normalDecoration = normalChip.decoration as BoxDecoration?;
    expect(normalDecoration?.color, Colors.transparent);
    expect(normalDecoration?.border, isNull);

    // 边界翻页钮禁用：回调为空且统一 45% 透明。
    final firstOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.byIcon(Icons.first_page_rounded),
        matching: find.byType(Opacity),
      ),
    );
    expect(firstOpacity.opacity, 0.45);
    final first = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.first_page_rounded),
        matching: find.byType(IconButton),
      ),
    );
    final prev = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_left_rounded),
        matching: find.byType(IconButton),
      ),
    );
    final next = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_right_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(first.onPressed, isNull, reason: '首页在第一页禁用');
    expect(prev.onPressed, isNull, reason: '上一页在第一页禁用');
    expect(next.onPressed, isNotNull);
  });

  testWidgets('桌面密度下分页控件为 28px 紧凑度量', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 平台覆写属于 foundation 全局变量：框架的 invariants 校验先于
    // tearDown 回调执行，必须在测试体内复位（try/finally 保证断言失败
    // 也不污染后续用例）。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: OmniNestTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Scaffold(
              body: WorkstationPaginationBar(
                currentPage: 0,
                totalPages: 12,
                totalElements: 115,
                rowsPerPage: 10,
                onPageChanged: (_) {},
                onRowsPerPageChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 页码 chip：28px 高、32px 最小宽、mono 数字。
      final chip = tester.widget<Container>(
        find
            .ancestor(of: find.text('1'), matching: find.byType(Container))
            .first,
      );
      expect(chip.constraints?.minHeight, 28);
      expect(chip.constraints?.minWidth, 32);

      // 翻页图标钮：16px 图标、28px 视觉边长。
      expect(
        tester.getSize(find.byIcon(Icons.first_page_rounded)),
        const Size(16, 16),
      );
      expect(
        tester.getSize(
          find
              .ancestor(
                of: find.byIcon(Icons.first_page_rounded),
                matching: find.byType(IconButton),
              )
              .first,
        ),
        const Size(28, 28),
      );

      // 每页条数下拉与跳页输入同为 28px 行高、跳页输入 64px 宽 mono。
      expect(
        tester.getSize(find.byType(MenuAnchor)).height,
        28,
        reason: '每页条数紧凑下拉与 chip 同高',
      );
      expect(tester.getSize(find.byType(TextField)).width, 64);
      final jumpStyle = tester.widget<TextField>(find.byType(TextField)).style;
      expect(jumpStyle?.fontFamily, AppTypography.monoFamily);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('页码折叠高亮与跳页输入回调', (tester) async {
    final visited = <int>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: WorkstationPaginationBar(
              currentPage: 5,
              totalPages: 12,
              totalElements: 115,
              rowsPerPage: 10,
              onPageChanged: visited.add,
              onRowsPerPageChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 折叠结果：1 … 5 6 7 … 12（当前页 6 高亮）。
    expect(find.text('1'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('…'), findsNWidgets(2));

    await tester.tap(find.text('12'));
    await tester.pump();
    expect(visited, contains(11), reason: '点击末页页码回调 0 基 11');

    await tester.enterText(find.byType(TextField), '3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(visited, contains(2), reason: '跳页输入 3 回调 0 基 2');
  });

  testWidgets('空态渲染占位提示', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: AdminDataTable(
              columns: const [AdminListColumn(key: 'name', label: '名称')],
              rowCount: 0,
              rowCellsBuilder: (context, index) => const <Widget>[],
              emptyState: AdminListEmptyState(message: 'empty-hint'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('empty-hint'), findsOneWidget);
  });

  testWidgets('复选框列渲染并回调勾选与禁用', (tester) async {
    final checked = <int>{0};
    final toggled = <(int, bool)>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: AdminDataTable(
              columns: const [AdminListColumn(key: 'name', label: '名称')],
              rowCount: 3,
              rowCellsBuilder: (context, index) => [Text('row-$index')],
              showCheckboxes: true,
              isChecked: (index) => checked.contains(index),
              isCheckDisabled: (index) => index == 2,
              onRowCheck: (index, value) => toggled.add((index, value)),
              allChecked: false,
              someChecked: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 表头全选框 + 三行复选框；禁用行无法交互。
    expect(find.byType(Checkbox), findsNWidgets(4));
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    expect(toggled, isEmpty, reason: '禁用行点击不产生回调');

    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    expect(toggled, contains((0, false)), reason: '行复选框可勾选回调');
  });
}
